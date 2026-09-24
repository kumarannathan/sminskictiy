-- Shared game configuration (ReplicatedStorage.SminskiShared.Config)
-- Read by both the server (economy, validation) and the client (gameplay, UI).

local Config = {}

---------------------------------------------------------------------------
-- RUN TUNING
---------------------------------------------------------------------------
Config.LaneWidth = 7
Config.SegmentLength = 80
Config.MaxSpeed = 120
Config.StudsPerMeter = 3.4

-- speed (studs/s) over time survived (seconds): relaxed -> "OH GOD"
Config.SpeedCurve = {
	{ 0, 50 }, { 30, 58 }, { 60, 72 }, { 120, 90 }, { 180, 104 }, { 300, 118 }, { 600, 120 },
}

function Config.SpeedAt(t)
	local c = Config.SpeedCurve
	if t <= c[1][1] then return c[1][2] end
	for i = 1, #c - 1 do
		local a, b = c[i], c[i + 1]
		if t <= b[1] then
			local k = (t - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * k
		end
	end
	return c[#c][2]
end

-- difficulty tier from time survived
function Config.TierAt(t)
	if t < 30 then return 1 elseif t < 60 then return 2 elseif t < 120 then return 3 end
	return 4
end

-- chase distance: 100 = safe, 0 = caught
Config.Chase = {
	Start = 55,          -- right after the intro the kid is close-ish
	Regen = 2.4,         -- per second of clean running
	RegenPerCombo = 0.5, -- extra per multiplier step
	Stumble = 38,        -- lost on a side bump
	DangerAt = 40,       -- warning UI + visible kid
}

-- combo multiplier thresholds (combo points needed for x1, x2, ...)
Config.ComboSteps = { 0, 30, 80, 150, 250, 400, 600, 900 }
Config.ComboPoints = { Coin = 1, Dodge = 5, Perfect = 10, NearMiss = 15, Chain = 25 }

---------------------------------------------------------------------------
-- ECONOMY
---------------------------------------------------------------------------
Config.CapsuleCost = 400
-- Capsules are random items. They only cost EARNED coins, so they are not
-- "paid random items". If you ever sell coins for Robux, set this to true:
-- the server then checks PolicyService.ArePaidRandomItemsRestricted and blocks
-- capsules for players where paid random items aren't allowed.
Config.CapsulesArePaid = false
Config.ReviveBaseCost = 250 -- coins; doubles with each paid revive in a run
-- Optional Robux revive: set to your Developer Product id (a number) to enable
Config.ReviveProductId = 3713434937
Config.GoldCoinValue = 10

Config.Rarities = {
	{ id = "Common", weight = 62, color = Color3.fromRGB(150, 200, 140), refund = 60 },
	{ id = "Rare", weight = 27, color = Color3.fromRGB(110, 170, 240), refund = 120 },
	{ id = "Epic", weight = 9, color = Color3.fromRGB(185, 130, 240), refund = 250 },
	{ id = "Secret", weight = 2, color = Color3.fromRGB(245, 195, 70), refund = 600 },
}

function Config.Rarity(id)
	for _, r in Config.Rarities do
		if r.id == id then return r end
	end
	return Config.Rarities[1]
end

-- Collectible Sminski variants from toy capsules. NOT purely cosmetic any
-- more: each one carries a gameplay passive (Config.Passives, below), and ten
-- of the fifteen change how far a run gets -- see Config.DistancePassives.
Config.Characters = {
	{ id = "Glow", name = "Glow", rarity = "Common", body = Color3.fromRGB(218, 238, 186), glow = Color3.fromRGB(190, 255, 150), trail = Color3.fromRGB(200, 255, 160), idle = "hide", default = true },
	{ id = "Blush", name = "Blush", rarity = "Common", body = Color3.fromRGB(250, 214, 214), glow = Color3.fromRGB(255, 180, 190), trail = Color3.fromRGB(255, 170, 190), idle = "peek" },
	{ id = "Sky", name = "Sky", rarity = "Common", body = Color3.fromRGB(205, 228, 250), glow = Color3.fromRGB(170, 215, 255), trail = Color3.fromRGB(160, 205, 255), idle = "yawn" },
	{ id = "Lemon", name = "Lemon", rarity = "Common", body = Color3.fromRGB(250, 240, 180), glow = Color3.fromRGB(255, 240, 150), trail = Color3.fromRGB(255, 230, 120), idle = "cheer" },
	{ id = "Lavender", name = "Lavender", rarity = "Rare", body = Color3.fromRGB(222, 208, 245), glow = Color3.fromRGB(200, 170, 255), trail = Color3.fromRGB(190, 160, 255), idle = "hug" },
	{ id = "Mint", name = "Mint", rarity = "Rare", body = Color3.fromRGB(190, 240, 222), glow = Color3.fromRGB(150, 255, 215), trail = Color3.fromRGB(130, 240, 200), idle = "yoga" },
	{ id = "Peach", name = "Peach", rarity = "Rare", body = Color3.fromRGB(252, 220, 190), glow = Color3.fromRGB(255, 200, 150), trail = Color3.fromRGB(255, 180, 130), idle = "sit" },
	{ id = "Ghost", name = "Ghost", rarity = "Epic", body = Color3.fromRGB(238, 246, 255), glow = Color3.fromRGB(190, 220, 255), trail = Color3.fromRGB(220, 235, 255), idle = "peek", ghost = true },
	{ id = "Night", name = "Night", rarity = "Epic", body = Color3.fromRGB(150, 235, 205), glow = Color3.fromRGB(120, 255, 220), trail = Color3.fromRGB(100, 255, 220), idle = "hug", neon = true },
	{ id = "Galaxy", name = "Galaxy", rarity = "Epic", body = Color3.fromRGB(120, 105, 190), glow = Color3.fromRGB(170, 140, 255), trail = Color3.fromRGB(200, 150, 255), idle = "cheer", neon = true },
	{ id = "Cocoa", name = "Cocoa", rarity = "Common", body = Color3.fromRGB(214, 176, 142), glow = Color3.fromRGB(240, 196, 150), trail = Color3.fromRGB(230, 180, 130), idle = "sit" },
	{ id = "Sakura", name = "Sakura", rarity = "Rare", body = Color3.fromRGB(255, 206, 222), glow = Color3.fromRGB(255, 170, 205), trail = Color3.fromRGB(255, 190, 215), idle = "hug" },
	{ id = "Aqua", name = "Aqua", rarity = "Rare", body = Color3.fromRGB(170, 236, 236), glow = Color3.fromRGB(120, 240, 240), trail = Color3.fromRGB(110, 230, 235), idle = "yoga" },
	{ id = "Ember", name = "Ember", rarity = "Epic", body = Color3.fromRGB(255, 176, 120), glow = Color3.fromRGB(255, 140, 70), trail = Color3.fromRGB(255, 130, 60), idle = "cheer", neon = true },
	{ id = "Secret", name = "Golden", rarity = "Secret", body = Color3.fromRGB(245, 205, 90), glow = Color3.fromRGB(255, 220, 120), trail = Color3.fromRGB(255, 215, 90), idle = "yoga", metal = true },
}

function Config.Character(id)
	for _, c in Config.Characters do
		if c.id == id then return c end
	end
	return Config.Characters[1]
end

-- Outfits: bought directly in the shop with coins, wearable on any Sminski.
Config.Outfits = {
	{ id = "None", name = "No Outfit", price = 0 },
	{ id = "bow", name = "Little Bow", price = 250 },
	{ id = "headband", name = "Yoga Band", price = 250 },
	{ id = "sprout", name = "Sprout", price = 300 },
	{ id = "nightcap", name = "Sleepy Cap", price = 350 },
	{ id = "tie", name = "Work Tie", price = 350 },
	{ id = "scarf", name = "Cozy Scarf", price = 450 },
	{ id = "party", name = "Party Hat", price = 450, level = 3 },
	{ id = "towel", name = "Bath Towel", price = 500 },
	{ id = "chefhat", name = "Chef Hat", price = 600 },
	{ id = "catears", name = "Cat Ears", price = 700 },
	{ id = "flowers", name = "Flower Crown", price = 800, level = 6 },
	{ id = "santa", name = "Holiday Hat", price = 900 },
	{ id = "backpack", name = "Tiny Backpack", price = 1000, level = 8 },
	{ id = "helmet", name = "Space Helmet", price = 1500, level = 10 },
	{ id = "shades", name = "Cool Shades", price = 400 },
	{ id = "beanie", name = "Mint Beanie", price = 550 },
	{ id = "bunny", name = "Bunny Ears", price = 750, level = 4 },
	{ id = "frog", name = "Frog Hat", price = 950, level = 5 },
	{ id = "wings", name = "Fairy Wings", price = 1800, level = 12 },
	{ id = "halo", name = "Little Halo", price = 2200, level = 15 },
	{ id = "daisy", name = "Daisy Clip", price = 0, exclusive = "Day 3 login gift" },
	{ id = "cape", name = "Starry Cape", price = 0, exclusive = "Day 7 login gift" },
	{ id = "crown", name = "Royal Crown", price = 3000 },
	{ id = "cherries", name = "Cherry Clip", price = 400 },
	{ id = "starclips", name = "Star Clips", price = 420 },
	{ id = "heartspecs", name = "Heart Specs", price = 480 },
	{ id = "bearears", name = "Teddy Ears", price = 520 },
	{ id = "lollipop", name = "Lollipop Pin", price = 560 },
	{ id = "strawberry", name = "Strawberry Hat", price = 650 },
	{ id = "sunhat", name = "Sun Hat", price = 700 },
	{ id = "duckfloat", name = "Duck Floatie", price = 850, level = 3 },
	{ id = "bee", name = "Bumble Bee", price = 900, level = 4 },
	{ id = "cloud", name = "Little Cloud", price = 1100, level = 6 },
	{ id = "mushroom", name = "Toadstool Cap", price = 1200, level = 7 },
	{ id = "unicorn", name = "Unicorn Horn", price = 1700, level = 9 },
}

function Config.Outfit(id)
	for _, o in Config.Outfits do
		if o.id == id then return o end
	end
	return Config.Outfits[1]
end

---------------------------------------------------------------------------
-- SKINS: whole-body looks. Three layers make up a Sminski and they are kept
-- separate on purpose, because they come from different places:
--
--   CHARACTER  the body colour and finish        <- toy capsules
--   SKIN       the shape you are wearing         <- bought here, below
--   OUTFIT     a hat or a clip on top            <- the Toy Shop
--
-- So a Golden Sminski in a ninja hood with a flower crown is three separate
-- things you collected three separate ways, and they all compose. A skin with
-- `keepBody` is dyed by whichever capsule character you have equipped, which
-- is why the tracksuit and the hoodie are the ones that show your collection
-- off; the rest set their own colour because a pink knight is not a knight.
---------------------------------------------------------------------------
Config.Skins = {
	{ id = "none", name = "Just Me", price = 0, desc = "No costume. Your Sminski as it comes." },
	{ id = "hoodie", name = "Cosy Hoodie", price = 400, keepBody = true,
		desc = "A big soft hood and a front pocket, in your own colour." },
	{ id = "tracksuit", name = "Tracksuit", price = 600, keepBody = true,
		desc = "Stripes down the arms and legs. Built for the kart track." },
	{ id = "chef", name = "Head Chef", price = 900, body = Color3.fromRGB(248, 246, 238),
		desc = "Whites, a neckerchief and a hat you can barely see over." },
	{ id = "bee", name = "Bumble Suit", price = 1100, body = Color3.fromRGB(252, 214, 88),
		desc = "Stripes, wings and two wobbly antennae." },
	{ id = "ninja", name = "Night Ninja", price = 1200, level = 4, body = Color3.fromRGB(46, 52, 74),
		desc = "Hood, face wrap and a red sash. Nobody sees you coming." },
	{ id = "ghost", name = "Bedsheet Ghost", price = 1300, body = Color3.fromRGB(242, 246, 252),
		desc = "A sheet with a ragged hem. Faintly see-through." },
	{ id = "diver", name = "Deep Diver", price = 1400, level = 5, body = Color3.fromRGB(46, 120, 132),
		desc = "Wetsuit, mask, air tank and a very big pair of flippers." },
	{ id = "pirate", name = "Captain", price = 1500, level = 6, body = Color3.fromRGB(122, 58, 62),
		desc = "A long coat, a tricorn hat and one closed eye." },
	{ id = "dino", name = "Little Dino", price = 1600, level = 7, body = Color3.fromRGB(122, 196, 116),
		desc = "Spines down the back, a fat tail, and a hood with teeth." },
	{ id = "robot", name = "Tin Sminski", price = 1800, level = 8, body = Color3.fromRGB(176, 184, 200), metal = true,
		desc = "Riveted plates, a chest panel and one wobbling antenna." },
	{ id = "wizard", name = "Star Wizard", price = 2000, level = 9, body = Color3.fromRGB(104, 84, 176),
		desc = "A wide pointed hat and a cape with stars on it." },
	{ id = "knight", name = "Knight", price = 2200, level = 10, body = Color3.fromRGB(196, 202, 216), metal = true,
		desc = "Plate armour, pauldrons and a visor with a slit." },
	{ id = "astronaut", name = "Astronaut", price = 2500, level = 12, body = Color3.fromRGB(246, 246, 250),
		desc = "A sealed suit, a bubble helmet and a life-support pack." },
	{ id = "golden", name = "Solid Gold", price = 12000, level = 15, body = Color3.fromRGB(245, 205, 90), metal = true,
		desc = "Entirely, unnecessarily gold. Everyone will look." },
}

function Config.Skin(id)
	for _, k in Config.Skins do
		if k.id == id then return k end
	end
	return Config.Skins[1]
end

-- Permanent upgrades bought with coins. They make runs more interesting
-- (longer powerups, more powerups, a revive) rather than multiplying numbers.
Config.Upgrades = {
	{ id = "Magnet", name = "Magnet", desc = "Coins fly to you. Upgrades add duration.", costs = { 250, 500, 900, 1500, 2400 }, base = 8, per = 2, unit = "s" },
	{ id = "Doubler", name = "2x Coins", desc = "Doubles coins picked up. Upgrades add duration.", costs = { 300, 600, 1000, 1700, 2600 }, base = 8, per = 2, unit = "s" },
	{ id = "Shield", name = "Shield Bubble", desc = "Absorbs one hit. Upgrades add duration.", costs = { 300, 600, 1000, 1700, 2600 }, base = 10, per = 3, unit = "s" },
	{ id = "SlowTime", name = "Slow Time", desc = "Everything slows down. Upgrades add duration.", costs = { 250, 500, 900, 1500, 2400 }, base = 5, per = 1, unit = "s" },
	{ id = "Boost", name = "Zoom Boost", desc = "Zoom ahead, invulnerable. Upgrades add duration.", costs = { 350, 700, 1200, 1900, 2800 }, base = 3.5, per = 0.8, unit = "s" },
	{ id = "Luck", name = "Lucky Finds", desc = "More powerups and golden coins spawn.", costs = { 400, 800, 1400, 2200, 3200 }, base = 0, per = 1, unit = "" },
	{ id = "SecondChance", name = "Second Chance", desc = "Free revives each run.", costs = { 1500, 4000 }, base = 0, per = 1, unit = "" },
}

function Config.Upgrade(id)
	for _, u in Config.Upgrades do
		if u.id == id then return u end
	end
	return nil
end

-- value of an upgrade at a given level (0 = not bought)
function Config.UpgradeValue(id, level)
	local u = Config.Upgrade(id)
	if not u then return 0 end
	return u.base + u.per * (level or 0)
end

Config.Powerups = {
	Magnet = { name = "MAGNET", icon = "🧲", color = Color3.fromRGB(255, 110, 110) },
	Doubler = { name = "2X COINS", icon = "x2", color = Color3.fromRGB(255, 205, 70) },
	Shield = { name = "SHIELD", icon = "🛡️", color = Color3.fromRGB(120, 190, 255) },
	SlowTime = { name = "SLOW TIME", icon = "⏳", color = Color3.fromRGB(170, 140, 255) },
	Boost = { name = "BOOST", icon = "⚡", color = Color3.fromRGB(255, 160, 60) },
}
Config.PowerupOrder = { "Magnet", "Doubler", "Shield", "SlowTime", "Boost" }

---------------------------------------------------------------------------
-- MAPS (solo). Paid maps unlock with coins, or a Robux game pass if you set
-- gamePassId (Creator Dashboard -> your experience -> Monetization -> Passes).
---------------------------------------------------------------------------
-- While testing in Studio every paid map is unlocked (never saved, so the
-- live game is unaffected). Set to false to test the buy flow in Studio.
Config.StudioUnlockMaps = true

Config.Maps = {
	{
		id = "house", name = "The Big House", icon = "🏠", free = true,
		desc = "Run from the kid through a giant house at night.",
		chaser = "kid", look = "night", color = Color3.fromRGB(150, 130, 230),
		zones = { "Hallway", "Kitchen", "LivingRoom", "Backyard", "Bathroom", "Bedroom" },
	},
	{
		id = "dollhouse", name = "Sminski Dollhouse", icon = "🏡", free = true,
		desc = "A glowing green dollhouse full of Sminskis. No kid: just you, the obstacles and 3 hearts.",
		chaser = nil, hearts = 3, look = "green", color = Color3.fromRGB(150, 215, 120),
		zones = { "GreenLounge", "GreenLibrary", "GreenBedroom", "GreenStairs" },
	},
	{
		id = "dogpark", name = "Dog Park", icon = "🐶", price = 7500, gamePassId = nil,
		desc = "A giant golden retriever wants to play fetch with you. Dodge stomping kids.",
		chaser = "dog", look = "day", color = Color3.fromRGB(120, 200, 110),
		zones = { "ParkPath", "ParkPlayground", "ParkPond" },
	},
}

function Config.Map(id)
	for _, m in Config.Maps do
		if m.id == id then return m end
	end
	return Config.Maps[1]
end

---------------------------------------------------------------------------
-- MULTIPLAYER
---------------------------------------------------------------------------
Config.MP = {
	MaxPlayers = 3,
	BotFillAfter = 10, -- quick play: seconds of "finding players" before bots take the empty spots
	RespawnBase = 5, -- first respawn wait (seconds); grows each time you go down
	RespawnStep = 2,
	CountdownLead = 4.5, -- seconds between "match found" and GO
	StartLanes = { 3, 2, 4 },
	ShoveChase = 10, -- chase lost when someone shoves you
	EloK = 32,
	StartElo = 1000,
}

-- Dog Park Survival (free-roam, last Sminski alive wins)
Config.Park = {
	MaxPlayers = 16,
	MinTotal = 6, -- empty spots fill with bots up to this many Sminskis
	Countdown = 20, -- seconds in the waiting pen once someone is in it
	StudioCountdown = 8,
	FullCountdown = 8, -- once the pen has 8+ players
	WalkSpeed = 26,
	JumpHeight = 5.5,
	FreezeTime = 4, -- 3-2-1 before the park wakes up
	ResultsTime = 9,
	MaxTime = 420, -- hard stop (7 min)
	-- heart pickups: one extra life at most, rare, and they vanish if ignored
	HeartMax = 1,
	HeartFirst = 20, -- none in the first 20s
	HeartEvery = { 22, 30 },
	HeartLife = 20,
	HeartSafe = 2.5, -- seconds of safety after a heart pops
	SpectateAfterOut = 30, -- once every player is out, bots play on this long for the spectators
}

-- ranked tiers, named after Sminski colours
Config.RankTiers = {
	{ id = "Glow", min = 0, color = Color3.fromRGB(190, 225, 160) },
	{ id = "Sky", min = 1100, color = Color3.fromRGB(150, 200, 245) },
	{ id = "Blush", min = 1250, color = Color3.fromRGB(245, 170, 185) },
	{ id = "Lemon", min = 1400, color = Color3.fromRGB(245, 215, 90) },
	{ id = "Mint", min = 1550, color = Color3.fromRGB(120, 220, 185) },
	{ id = "Lavender", min = 1700, color = Color3.fromRGB(185, 160, 240) },
	{ id = "Night", min = 1850, color = Color3.fromRGB(80, 200, 175) },
	{ id = "Galaxy", min = 2000, color = Color3.fromRGB(130, 100, 210) },
	{ id = "Golden", min = 2200, color = Color3.fromRGB(245, 195, 70) },
}

function Config.RankTier(elo)
	local tier, nextTier = Config.RankTiers[1], nil
	for i, t in Config.RankTiers do
		if elo >= t.min then
			tier = t
			nextTier = Config.RankTiers[i + 1]
		end
	end
	return tier, nextTier
end

-- difficulty from distance (not time) so every player in a match builds the same world
function Config.TierAtDistance(z)
	if z < 1600 then return 1 elseif z < 3600 then return 2 elseif z < 8400 then return 3 end
	return 4
end

---------------------------------------------------------------------------
-- PROGRESSION
---------------------------------------------------------------------------
function Config.XPForRun(distanceStuds, coins, nearMisses)
	return math.floor(distanceStuds / Config.StudsPerMeter / 5 + coins * 0.5 + nearMisses * 4)
end

function Config.LevelFromXP(xp)
	-- level n needs 100 * (n-1)^1.6 total xp
	local lvl = 1
	while 100 * (lvl ^ 1.6) <= xp do
		lvl += 1
	end
	return lvl
end

function Config.XPForLevel(lvl)
	if lvl <= 1 then return 0 end
	return 100 * ((lvl - 1) ^ 1.6)
end

---------------------------------------------------------------------------
-- AUDIO (licensed Roblox library sounds: APM Music / Pro Sound Effects)
---------------------------------------------------------------------------
Config.Sounds = {
	-- Music layers: add stems of the same song here (same length/tempo) and
	-- they fade in by intensity. With one layer, intensity drives tempo + EQ.
	MusicLayers = {
		{ id = "rbxassetid://9046862941", from = 0, volume = 0.45 }, -- "Sunset Chill (Bed Version)"
	},
	Heartbeat = "rbxassetid://9043365842",
	Stomp = "rbxassetid://9113481994",
	Tick = "rbxassetid://9125759090",
	Click = "rbxassetid://9119727934",
	Whoosh = "rbxassetid://9126015464",
	Pop = "rbxassetid://132948338000932",
	Chime = "rbxassetid://4612374495",
	BigChime = "rbxassetid://98646737427339",
	Wobble = "rbxassetid://96068697250195",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Bump = "rbxasset://sounds/ouch.ogg",
	Bark = "rbxassetid://123024926216748",
	Lobby = "rbxassetid://130465591471764", -- "Cozy After Work" (lofi, Creator Store)

	-- THE CITY'S WORLD SOUND. Every id below was probed in-engine and loads;
	-- they are engine built-ins, so they need no marketplace lookup and cannot
	-- go missing. They are raw material, not finished sounds -- CitySound
	-- shapes each one with PlaybackSpeed, looping and an equaliser (a wind
	-- rush low-passed is a distant sea; pitched down it is a diesel engine).
	City = {
		Air = "rbxasset://sounds/action_falling.mp3",      -- 10.0s wind rush: rain, wind, tyre roar
		Water = "rbxasset://sounds/action_swim.mp3",       --  4.9s water movement: the sea, the creek
		Splash = "rbxasset://sounds/impact_water.mp3",     --  2.4s
		Tone = "rbxasset://sounds/bass.mp3",               --  1.0s low tone: engines, train rumble, thunder
		Step = "rbxasset://sounds/action_footsteps_plastic.mp3",
		Switch = "rbxasset://sounds/switch.wav",           -- doors, lifts
		Snap = "rbxasset://sounds/snap.mp3",               -- fire crackle, latches
		Ping = "rbxasset://sounds/electronicpingshort.wav",-- tills, birds (pitched up)
		Voice = "rbxasset://sounds/uuhhh.mp3",             -- crowd chatter, pitched per person
		Click = "rbxasset://sounds/clickfast.wav",
	},
}

---------------------------------------------------------------------------
-- CHARACTER PASSIVES + PERSONALITIES (every Sminski has a reason to exist)
---------------------------------------------------------------------------
Config.Passives = {
	Glow = { name = "Night Light", desc = "Coins pull in from further away.", magnet = 1.6, bio = "The original. Glows in the dark and never stops smiling." },
	Blush = { name = "Second Wind", desc = "Stumbles cost 25% less chase.", stumble = 0.75, bio = "Easily embarrassed, impossible to discourage." },
	Sky = { name = "Featherlight", desc = "Falls slower after a jump.", gravity = 0.8, bio = "Always yawning. Dreams about clouds." },
	Lemon = { name = "Lucky Lemon", desc = "+1 Lucky Finds level.", luck = 1, bio = "Cheers for everyone, including the kid." },
	Lavender = { name = "Calm Mind", desc = "Combos cool off half as fast.", comboCool = 0.5, bio = "Gives the best hugs on the table." },
	Mint = { name = "Fresh Legs", desc = "Powerups last 15% longer.", power = 1.15, bio = "Does yoga at 6am. Every day." },
	Peach = { name = "Sweet Tooth", desc = "Golden coins are worth 50% more.", gold = 1.5, bio = "Sits down whenever possible." },
	Ghost = { name = "Phase", desc = "A free shield at the start of every run.", startShield = true, bio = "Was here the whole time. You just didn't notice." },
	Night = { name = "Night Owl", desc = "Chase recovers 20% faster.", regen = 1.2, bio = "Only comes out after the lamp goes off." },
	Galaxy = { name = "Stardust", desc = "+15% score at the end of a run.", score = 1.15, bio = "Claims to be from space. Probably from a capsule." },
	Cocoa = { name = "Pocket Change", desc = "Starts every run with 25 coins.", startCoins = 25, bio = "Smells faintly of hot chocolate. Naps in the sun." },
	Sakura = { name = "Soft Landing", desc = "Hearts regrow twice as fast on hearts maps.", heartRegen = 2, bio = "Only blooms once a year. Makes it count." },
	Aqua = { name = "Splash", desc = "Near misses count double for combos.", nearMiss = 2, bio = "Loves puddles. The kid hates it." },
	Ember = { name = "Afterburn", desc = "Zoom Boost lasts 25% longer.", boost = 1.25, bio = "Always running a little warm." },
	Secret = { name = "Midas", desc = "Every coin is worth double.", coin = 2, bio = "Nobody has seen it up close. Rumours say it's gold." },
}
function Config.Passive(id)
	return Config.Passives[id] or {}
end

---------------------------------------------------------------------------
-- WHICH PASSIVES CAN LENGTHEN A RUN (the all-time distance board)
--
-- Capsules are reachable with Robux, so any passive that helps you survive
-- longer is Robux buying rank on a board that is supposed to say who is best.
-- A run only goes to the distance board if the equipped Sminski's passive
-- cannot affect how far it got.
--
-- EVERY ENTRY BELOW IS A USE SITE, NOT A READING OF THE DESCRIPTION. The
-- chase meter is the death clock, so anything feeding it counts:
--
--   stumble     SmiskiRunner :1305  chase -= Stumble * stumble
--   regen       SmiskiRunner :2065  chase += Regen * regen
--   gravity     SmiskiRunner :1937  fall speed -- clears longer gaps
--   power       SmiskiRunner :1323  powerup duration, Shield included
--   boost       SmiskiRunner :1323  Zoom Boost duration
--   startShield SmiskiRunner :576   a free shield every run
--   luck        SmiskiRunner :393   Lucky Finds level -- more powerups
--   heartRegen  SmiskiRunner :2057  hearts regrow (hearts maps)
--   comboCool   SmiskiRunner :2050  holds the combo up, and :2065 regenerates
--                                   chase per combo step -- indirect but real
--   nearMiss    SmiskiRunner :1544  same path: more combo, more chase regen
--
-- The five that are NOT here -- magnet, gold, score, startCoins, coin -- touch
-- only currency or the end-of-run score readout, never the chase meter, the
-- powerup economy, gravity or hearts. They leave Glow (the default every
-- player owns), Peach, Galaxy, Cocoa and Secret rankable.
--
-- Add a passive field to Config.Passives without deciding which side of this
-- line it sits on and the board quietly stops meaning anything.
---------------------------------------------------------------------------
Config.DistancePassives = {
	stumble = true, regen = true, gravity = true, power = true, boost = true,
	startShield = true, luck = true, heartRegen = true, comboCool = true, nearMiss = true,
}
-- true when a run by this character may be compared with anyone else's
function Config.RanksForDistance(charId)
	local pv = Config.Passive(charId)
	for field in Config.DistancePassives do
		if pv[field] ~= nil then return false end
	end
	return true
end

---------------------------------------------------------------------------
-- RUNNER CHAOS METER: tiers by time, random events between them
---------------------------------------------------------------------------
Config.RunTiers = {
	{ t = 0, name = "WARM UP" },
	{ t = 25, name = "HEATING UP" },
	{ t = 55, name = "CHAOS" },
	{ t = 95, name = "MAYHEM" },
	{ t = 150, name = "BEDLAM" },
}
function Config.RunTierAt(t)
	local tier = 1
	for i, r in Config.RunTiers do
		if t >= r.t then tier = i end
	end
	return tier
end
Config.RunEvents = {
	lights = { title = "LIGHTS OUT!", dur = 7, maps = { house = true } },
	zoom = { title = "SUGAR RUSH!", dogTitle = "ZOOMIES!", dur = 8, needChaser = true },
	rain = { title = "COIN RAIN!", dur = 8 },
	slippery = { title = "SLIPPERY FLOOR!", dur = 8 },
	avalanche = { title = "TOY AVALANCHE!", dur = 2, minTier = 3 },
}
-- what the chaser yells, by chaos tier
Config.VoiceLines = {
	kid = {
		{ "Come back here!", "Where'd you go?", "I just wanna play!" },
		{ "I see you!", "Gotcha... almost!", "Stop running!" },
		{ "You can't hide!", "MINE!", "Hold still!" },
		{ "NO ESCAPE!", "I'm not tired!", "GRRR!" },
		{ "THIS IS MY HOUSE!", "RAAAH!", "GIVE UP!" },
	},
	dog = {
		{ "woof?", "sniff sniff", "arf!" },
		{ "WOOF!", "bork bork", "arf arf arf!" },
		{ "AWOOOO!", "WOOF WOOF!", "BORK!" },
		{ "BALL?! BALL!", "RUFF RUFF RUFF!", "AWOOOOOO!" },
		{ "WOOFWOOFWOOF", "BORKBORKBORK", "ZOOMIES!!!" },
	},
}

---------------------------------------------------------------------------
-- MAP MASTERY: stars per map from your best distance (metres), coins per star
---------------------------------------------------------------------------
Config.Mastery = { starsM = { 500, 1500, 3000 }, rewards = { 200, 600, 1500 } }
function Config.MasteryStars(bestStuds)
	local m = (bestStuds or 0) / Config.StudsPerMeter
	local n = 0
	for _, g in Config.Mastery.starsM do
		if m >= g then n += 1 end
	end
	return n
end

---------------------------------------------------------------------------
-- DAILY / WEEKLY CHALLENGES (same set for everyone, seeded by the date)
---------------------------------------------------------------------------
Config.ChallengePool = {
	daily = {
		{ id = "coins", text = "Collect %d coins", goals = { 150, 300, 500 }, stat = "coins", reward = 150 },
		{ id = "dist", text = "Run %dm in one run", goals = { 400, 800, 1500 }, stat = "runM", reward = 200, mode = "max" },
		{ id = "near", text = "Get %d near misses", goals = { 10, 25, 50 }, stat = "near", reward = 150 },
		{ id = "runs", text = "Finish %d runs", goals = { 3, 5, 8 }, stat = "runs", reward = 120 },
		{ id = "harvest", text = "Harvest %d plants in the garden", goals = { 2, 4, 6 }, stat = "harvest", reward = 150 },
		{ id = "park", text = "Play %d Dog Park round(s)", goals = { 1, 2, 3 }, stat = "parkPlayed", reward = 200 },
		{ id = "survive", text = "Survive %ds in the Dog Park", goals = { 60, 120, 180 }, stat = "parkBest", reward = 250, mode = "max" },
		{ id = "combo", text = "Reach a x%d combo", goals = { 3, 4, 5 }, stat = "combo", reward = 150, mode = "max" },
	},
	weekly = {
		{ id = "wcoins", text = "Collect %d coins", goals = { 2000, 4000 }, stat = "coins", reward = 800 },
		{ id = "wdist", text = "Run %dm in total", goals = { 5000, 10000 }, stat = "totalM", reward = 1000 },
		{ id = "wwin", text = "Win %d Dog Park round(s)", goals = { 1, 2 }, stat = "parkWins", reward = 1200 },
		{ id = "wcaps", text = "Open %d capsules", goals = { 3, 5 }, stat = "capsules", reward = 600 },
		{ id = "wruns", text = "Finish %d runs", goals = { 15, 25 }, stat = "runs", reward = 700 },
	},
}
Config.ChallengeCounts = { daily = 3, weekly = 2 }

---------------------------------------------------------------------------
-- GAME PASSES (Creator Dashboard -> your experience -> Monetization -> Passes).
-- Create each pass there, then paste its id into gamePassId. A pass with no
-- id shows as "COMING SOON" in the shop. None of them affect Dog Park
-- Survival, so nothing here is pay-to-win against other players.
---------------------------------------------------------------------------
Config.Passes = {
	{ id = "vip", name = "VIP", gamePassId = 1985150959, robux = 299, icon = "crown", color = Color3.fromRGB(245, 196, 80),
		perks = { "+25% coins from every run and round", "Royal Crown outfit, free", "Crown next to your name in the lobby" }, coinMult = 1.25, outfit = "crown" },
	{ id = "double", name = "2x COINS", gamePassId = 1987184540, robux = 399, icon = "x2", color = Color3.fromRGB(255, 160, 60),
		perks = { "Double coins from every run and Dog Park round", "Stacks with VIP" }, coinMult = 2 },
	{ id = "maps", name = "ALL MAPS", gamePassId = 1982169176, robux = 249, icon = "pin", color = Color3.fromRGB(120, 200, 110),
		perks = { "Unlocks every Endless Run map", "Includes maps added later" }, allMaps = true },
	{ id = "revive", name = "SECOND WIND", gamePassId = 1986302702, robux = 149, icon = "heart", color = Color3.fromRGB(255, 125, 150),
		perks = { "+1 free revive in every run" }, freeRevive = 1 },
	-- Sminski City passes: paste each pass's id into gamePassId once it's created
	{ id = "garage", name = "DREAM GARAGE", gamePassId = 1987262762, robux = 349, icon = "play", color = Color3.fromRGB(120, 180, 250),
		perks = { "Unlocks all 6 cars in Sminski City", "Includes cars added later" }, allCars = true },
	{ id = "citypro", name = "CITY PRO", gamePassId = 1986842826, robux = 249, icon = "bag", color = Color3.fromRGB(110, 200, 160),
		perks = { "+50% coins from every city job", "Deliveries, taxi, tidy-up, farm and kart races", "Stacks with 2x Coins and VIP" }, cityJobMult = 1.5 },
	{ id = "tycoon", name = "TYCOON", gamePassId = 1986950795, robux = 449, icon = "chart", color = Color3.fromRGB(190, 150, 250),
		perks = { "Your businesses earn 2x coins", "They keep earning for 8 hours offline instead of 4" }, bizMult = 2, bizCapMult = 2 },
	{ id = "greenthumb", name = "GREEN THUMB", gamePassId = 1987046785, robux = 129, icon = "star", color = Color3.fromRGB(150, 210, 110),
		perks = { "All 6 garden plots unlocked", "Bed-time bonus at home pays double" }, allPlots = true, sleepMult = 2 },
	{ id = "starter", name = "STARTER PACK", gamePassId = 1986537277, robux = 49, icon = "bag", color = Color3.fromRGB(255, 170, 120),
		perks = { "5,000 coins to get you going", "The Sminski Van, free", "A garden plot unlocked" },
		starter = true, starterCoins = 5000, starterCar = "van", starterPlots = 1 },
	{ id = "auto", name = "AUTO-COLLECT", gamePassId = 1987281225, robux = 199, icon = "gear", color = Color3.fromRGB(140, 190, 240),
		perks = { "Your shops cash themselves out every finished shift", "So you never miss the +50% completion bonus", "Keeps doing it while you are away" }, autoCollect = true },
	{ id = "speed", name = "QUICK FEET", gamePassId = 1981269868, robux = 149, icon = "bolt", color = Color3.fromRGB(120, 220, 200),
		perks = { "Walk 1.6x faster everywhere", "Your cars are 15% quicker too" }, walkMult = 1.6, carMult = 1.15 },
	-- RESTAURANT ROW (docs/TYCOON.md). gamePassId 0 = not created yet, so it
	-- shows as COMING SOON and grants nothing. TYCOON and AUTO-COLLECT above
	-- already apply to a restaurant's passive takings, exactly as to a shop.
	{ id = "restaurateur", name = "RESTAURATEUR", gamePassId = 0, robux = 299, icon = "heart", color = Color3.fromRGB(240, 150, 80),
		perks = { "Your restaurant's stockroom holds twice as much", "Two extra chain locations", "A gold sign over the door" },
		tycoonStockMult = 2, tycoonChains = 2, goldSign = true },
}

---------------------------------------------------------------------------
-- DEVELOPER PRODUCTS (buy again and again, unlike a pass)
--
-- EVERY productId BELOW IS 0 AND MUST BE FILLED IN. Developer products are
-- created on the Roblox creator dashboard, not from code, so these are
-- placeholders: anything with productId 0 is hidden from the shop and can
-- never be purchased, which means shipping this file as-is is safe.
--
-- Grants are applied SERVER-SIDE in ProcessReceipt and every receipt is
-- recorded by PurchaseId, because Roblox calls ProcessReceipt again after a
-- failed save and a player would otherwise be paid twice for one purchase.
---------------------------------------------------------------------------
Config.Products = {
	-- CASH. Value per Robux climbs with the tier, so the big one is the deal.
	{ id = "coins1", kind = "coins", productId = 3713946196, robux = 49, coins = 3000,
		name = "POCKET CHANGE", icon = "coin", color = Color3.fromRGB(245, 196, 80) },
	{ id = "coins2", kind = "coins", productId = 0, robux = 99, coins = 7500, badge = "+25%",
		name = "COIN JAR", icon = "coin", color = Color3.fromRGB(245, 196, 80) },
	{ id = "coins3", kind = "coins", productId = 3713946250, robux = 249, coins = 22000, badge = "+47%",
		name = "BRIEFCASE", icon = "coin", color = Color3.fromRGB(250, 170, 60) },
	{ id = "coins4", kind = "coins", productId = 3713946313, robux = 499, coins = 50000, badge = "BEST VALUE",
		name = "VAULT", icon = "coin", color = Color3.fromRGB(250, 140, 60) },
	-- SKIPS. The city already has waits: businesses bank up over time and
	-- garden plots ripen. These finish one instantly.
	{ id = "skipbiz", kind = "skipBiz", productId = 3713946288, robux = 25,
		name = "COLLECT NOW", icon = "chart", color = Color3.fromRGB(190, 150, 250),
		desc = "Every shop you own jumps to a finished shift, bonus and all. Collect it now." },
	{ id = "skipfarm", kind = "skipFarm", productId = 3713946335, robux = 25,
		name = "RIPEN NOW", icon = "star", color = Color3.fromRGB(150, 210, 110),
		desc = "Every planted garden plot ripens instantly." },
	-- BOOSTS. Server-wide ones are deliberate: the whole server sees who
	-- bought it, which is the point of them.
	{ id = "boost2x", kind = "boost", productId = 3713947044, robux = 75, mult = 2, minutes = 15, scope = "me",
		name = "2x COINS - 15 MIN", icon = "x2", color = Color3.fromRGB(255, 160, 60) },
	{ id = "boost2xs", kind = "boost", productId = 3713946975, robux = 199, mult = 2, minutes = 15, scope = "server",
		name = "2x FOR EVERYONE", icon = "friends", color = Color3.fromRGB(255, 125, 110),
		desc = "15 minutes of double coins for every player on this server. Your name is on it." },
	{ id = "boost2xs30", kind = "boost", productId = 3713947011, robux = 349, mult = 2, minutes = 30, scope = "server",
		name = "2x FOR EVERYONE - 30 MIN", icon = "friends", color = Color3.fromRGB(255, 100, 110) },
	-- RESTAURANT ROW (docs/TYCOON.md). All productId 0 until created on the
	-- dashboard; hidden from the shop and unpurchasable until then. None of
	-- these buy a rate: they buy time (a rush, a full stockroom) or skip a
	-- coin price the player could have earned.
	{ id = "tycoonrush", kind = "tycoonRush", productId = 0, robux = 49, minutes = 15, mult = 3,
		name = "RUSH HOUR", icon = "friends", color = Color3.fromRGB(240, 150, 80),
		desc = "15 minutes of triple customers at your restaurant. Keep the stockroom full." },
	{ id = "tycoonpantry", kind = "tycoonPantry", productId = 0, robux = 25,
		name = "FULL STOCKROOM", icon = "bag", color = Color3.fromRGB(120, 200, 110),
		desc = "Your restaurant's stockroom fills to the top, every ingredient." },
	{ id = "tycoonchain", kind = "tycoonChain", productId = 0, robux = 199,
		name = "FRANCHISE LICENSE", icon = "chart", color = Color3.fromRGB(190, 150, 250),
		desc = "Open your next chain location now, whatever your stars." },
}
function Config.Product(id)
	for _, p in Config.Products do
		if p.id == id then return p end
	end
	return nil
end
function Config.ProductByAssetId(assetId)
	for _, p in Config.Products do
		if p.productId ~= 0 and p.productId == assetId then return p end
	end
	return nil
end

-- Studio only: pretend to own every pass (never saved). Handy for testing perks.
Config.StudioOwnPasses = false
function Config.Pass(id)
	for _, p in Config.Passes do
		if p.id == id then return p end
	end
	return nil
end

---------------------------------------------------------------------------
-- SMINSKI GARDEN: plant seeds, wait (real time, even offline), harvest for coins.
-- Watering once per plant cuts the remaining time by a third.
---------------------------------------------------------------------------
Config.Seeds = {
	{ id = "sprout", name = "Glow Sprout", cost = 20, grow = 60, sell = 45, xp = 4, color = Color3.fromRGB(170, 240, 110), level = 1 },
	{ id = "berry", name = "Star Berry", cost = 60, grow = 180, sell = 150, xp = 10, color = Color3.fromRGB(255, 120, 150), level = 1 },
	{ id = "tulip", name = "Pastel Tulip", cost = 120, grow = 420, sell = 320, xp = 18, color = Color3.fromRGB(190, 160, 250), level = 3 },
	{ id = "bloom", name = "Moon Bloom", cost = 250, grow = 900, sell = 700, xp = 30, color = Color3.fromRGB(150, 210, 255), level = 5 },
	{ id = "shroom", name = "Lamp Shroom", cost = 600, grow = 2400, sell = 1800, xp = 60, color = Color3.fromRGB(255, 196, 110), level = 8 },
	{ id = "golden", name = "Golden Sminski Pod", cost = 1500, grow = 7200, sell = 5200, xp = 140, color = Color3.fromRGB(255, 214, 80), level = 12 },
}
Config.Garden = {
	StartPlots = 3,
	MaxPlots = 6,
	PlotCosts = { 400, 1200, 3000 }, -- plots 4, 5, 6
	WaterCut = 1 / 3,
}
function Config.Seed(id)
	for _, s in Config.Seeds do
		if s.id == id then return s end
	end
	return nil
end

---------------------------------------------------------------------------
-- DAILY LOGIN: a 7-day gift calendar (loops), and a streak coin multiplier
-- (+10% per day in a row, up to +50%) on everything you earn.
---------------------------------------------------------------------------
Config.Daily = {
	{ coins = 100, label = "100 coins" },
	{ coins = 200, label = "200 coins" },
	{ outfit = "daisy", coins = 150, fallbackCoins = 450, label = "Daisy Clip outfit" },
	{ coins = 350, label = "350 coins" },
	{ capsule = true, label = "free capsule" },
	{ coins = 500, label = "500 coins" },
	{ outfit = "cape", coins = 500, fallbackCoins = 1500, label = "Starry Cape + 500" },
}
Config.Streak = { per = 0.1, max = 0.5 }
function Config.StreakMult(streak)
	return 1 + math.min(Config.Streak.max, math.max(0, (streak or 1) - 1) * Config.Streak.per)
end

---------------------------------------------------------------------------
-- SMINSKI CITY economy: the city is a second way to earn (and spend) the
-- same coins as the runner. Jobs pay, businesses earn while you're away,
-- and cars / rides / the claw machine are the coin sinks. Every payout goes
-- through the server's pass multiplier (2x Coins pass, login streak).
---------------------------------------------------------------------------
Config.City = {
	-- PLACES TO LIVE. Five buildings spread across town, five floor plans.
	-- What you pay is the building's base price x the plan's multiplier, so a
	-- studio in the townhouses is the cheap way in and a downtown penthouse is
	-- something to save for. One plan per building; buying another replaces it.
	AptBuildings = {
		{ id = "bankside", name = "BANKSIDE TOWER", kind = "tower", base = 4000, blurb = "Downtown. A doorman, and the whole skyline." },
		{ id = "motorrow", name = "MOTOR ROW LOFTS", kind = "tower", base = 3000, blurb = "East side, next to the dealer. Park it, go up." },
		{ id = "funfair", name = "FUNFAIR HEIGHTS", kind = "tower", base = 2600, blurb = "Over the fun park. You can hear the carousel." },
		{ id = "mochi", name = "MOCHI BROWNSTONES", kind = "brownstone", base = 2000, blurb = "Brick, stoops and fire escapes on the quiet side." },
		{ id = "willow", name = "WILLOW ROW", kind = "townhouse", base = 1500, blurb = "A townhouse on a garden street, by the creek." },
	},
	AptPlans = {
		{ id = "studio", name = "STUDIO", mult = 1, desc = "One bright room. Everything within reach." },
		{ id = "onebed", name = "ONE BEDROOM", mult = 1.8, desc = "A proper bedroom and room for a table." },
		{ id = "loft", name = "LOFT", mult = 2.6, desc = "Double height, a sleeping deck, huge windows." },
		{ id = "family", name = "FAMILY FLAT", mult = 3.4, desc = "Two bedrooms, a big kitchen, a tub." },
		{ id = "penthouse", name = "PENTHOUSE", mult = 6, desc = "The top floor. A terrace. A piano. Obviously." },
	},
	-- cars you can own (the convertible is free); speed in studs/s
	Cars = {
		{ id = "convertible", name = "Convertible", price = 0, speed = 72, desc = "Every Sminski's first car." },
		{ id = "van", name = "Sminski Van", price = 1200, speed = 68, desc = "Room for the whole family." },
		{ id = "taxi", name = "Taxi", price = 2500, speed = 76, desc = "Taxi fares pay +50%." },
		{ id = "icecream", name = "Ice Cream Truck", price = 4000, speed = 64, desc = "Sweeps litter from further away, +2 coins each." },
		{ id = "sports", name = "Sports Car", price = 9000, speed = 115, desc = "The fastest thing in the valley." },
		{ id = "monster", name = "Monster Truck", price = 20000, speed = 95, desc = "Huge wheels. Huge honk." },
	},
	CarColors = 8,
	-- businesses you can buy; they earn coins/minute, up to CapMinutes of
	-- earnings waiting, and you collect in person
	Businesses = {
		{ id = "boba", name = "Bubble Tea", price = 1500, rate = 6 },
		{ id = "sweets", name = "Sweet Shop", price = 4000, rate = 15 },
		{ id = "toys", name = "Toy Store", price = 9000, rate = 32 },
		{ id = "pizza", name = "Pizza Place", price = 18000, rate = 60 },
		{ id = "cinema", name = "Cinema", price = 35000, rate = 110 },
		{ id = "arcade", name = "Arcade", price = 60000, rate = 180 },
	},
	CapMinutes = 240,
	-- A SHIFT. A shop banks coins the whole time it is shut, up to CapMinutes.
	-- But the first ShiftMinutes are a SHIFT: cash out mid-shift and you get
	-- exactly what has piled up; let the shift run to the end and the whole
	-- payout comes with ShiftBonus on top. That turns the card into a choice
	-- (take it now, or let it ride) instead of a chore, and it is why
	-- AUTO-COLLECT is worth owning -- it always waits for the bonus.
	ShiftMinutes = 20,
	ShiftBonus = 0.5,
	Rides = { ferris = 25, carousel = 10 }, -- VIP rides free
	Claw = { price = 40 },
	Race = { entry = 15, gold = 30, par = 42, goldPay = 200, parPay = 80, finishPay = 20 },
	Taxi = { base = 25, perStud = 1 / 6 },
	Delivery = { base = 30, perStud = 1 / 8 },
	Sweep = 4,
	Harvest = 10,
	RipeSeconds = 45,
}
function Config.AptBuilding(id)
	for _, b in Config.City.AptBuildings do
		if b.id == id then return b end
	end
	return nil
end
function Config.AptPlan(id)
	for _, p in Config.City.AptPlans do
		if p.id == id then return p end
	end
	return nil
end
function Config.AptPrice(b, p) return math.floor(b.base * p.mult / 50 + 0.5) * 50 end

function Config.CityCar(id)
	for _, c in Config.City.Cars do
		if c.id == id then return c end
	end
	return nil
end
function Config.CityBiz(id)
	for _, b in Config.City.Businesses do
		if b.id == id then return b end
	end
	return nil
end

---------------------------------------------------------------------------
-- ROLES: where you start, not what you are.
--
-- A new player picks one of these before the city loads. It decides two
-- things and no others: which neighbourhood you spawn in, and which job the
-- GPS path leads to on your first morning.
--
-- IT IS NOT A CLASS. Every job in Config.Jobs stays open to every player --
-- job reputation is ONE number across all of them (see JOB REPUTATION
-- below), so there is nothing to specialise into and nothing to regret. A
-- permanent career choice is a terrible first decision for somebody who has
-- seen none of the game, and the ones who feel locked in leave.
--
-- SWITCHING COSTS SwitchCost COINS, and that is the whole penalty. Enough
-- that it reads as a decision, cheap enough that a player who picked wrong
-- at minute zero is not stuck with it. Switching changes your role and your
-- starting job; it does NOT move your home, because by then you live
-- somewhere you chose.
--
-- THREE, NOT SIX. A role has to spawn you beside a job you can actually do.
-- Everything else in Config.Jobs is still `soon = true`, and a neighbourhood
-- built around a job with no gameplay behind it is worse than no role at
-- all. Append here as jobs finish -- this list is read by id, never index.
---------------------------------------------------------------------------
Config.Roles = {
	{ id = "farmer", name = "FARMER", job = "farmhand", hood = "meadow",
		icon = "star", color = Color3.fromRGB(170, 210, 110),
		blurb = "Grow it, haul it into town, sell it.",
		tag = "A little farm on the edge of the valley." },
	{ id = "driver", name = "DRIVER", job = "taxi", hood = "motorrow",
		icon = "pin", color = Color3.fromRGB(245, 196, 80),
		blurb = "Fares across town. Drive well and they tip.",
		tag = "A flat over the garages, and the whole city as your office." },
	{ id = "cook", name = "COOK", job = "pizzeria", hood = "market",
		icon = "heart", color = Color3.fromRGB(226, 100, 90),
		blurb = "Take the order, make it, serve it.",
		tag = "Above the market, where the city eats." },
}
Config.RoleSwitchCost = 100
function Config.Role(id)
	for _, r in Config.Roles do
		if r.id == id then return r end
	end
	return nil
end

---------------------------------------------------------------------------
-- CROPS: the Farmer job. See docs/FARMING.md.
--
-- Times are SECONDS OF REAL TIME and growth is a pure function of a stored
-- plantedAt -- nothing ticks, nothing runs while you are away, and a crop
-- that is ready STAYS ready forever. Sixty players farming twelve plots
-- each costs the server zero work per frame, which is the whole reason the
-- record is a timestamp and not an object.
--
-- WATERING IS NOT BABYSITTING. Once per crop is all it ever wants, and an
-- unwatered crop is slow rather than dead. Missing it is a choice you made,
-- never a punishment for being somewhere else.
--
-- ONE CONSTANT, NOT A NUMBER PER CROP. docs/FARMING.md quotes a fertilised
-- time for each crop; those are all ~0.7 of base, so this is one FertCut to
-- tune instead of three that drift apart.
---------------------------------------------------------------------------
Config.Crops = {
	{ id = "carrot", name = "Carrot", seed = 6, grow = 300, sell = 8, yield = { 5, 8 }, xp = 3,
		color = Color3.fromRGB(255, 150, 70), level = 1 },
	{ id = "tomato", name = "Tomato", seed = 14, grow = 480, sell = 14, yield = { 4, 7 }, xp = 6,
		color = Color3.fromRGB(240, 90, 80), level = 1 },
	{ id = "corn", name = "Corn", seed = 26, grow = 720, sell = 22, yield = { 3, 6 }, xp = 10,
		color = Color3.fromRGB(250, 210, 90), level = 2 },
}
Config.Farm = {
	-- WATERING IS FREE, SO IT IS THE SMALLER BOOST. This was 1/3, copied
	-- from Config.Garden -- which made the free action BETTER than the 25
	-- coin one and turned fertiliser into a trap. The headless economy test
	-- caught it. Fertiliser now matches the 0.7x of base that
	-- docs/FARMING.md quotes, and watering sits below it.
	WaterCut = 0.2,     -- watering removes a fifth of the REMAINING time
	FertCut = 0.3,      -- fertiliser removes 30% -- always more than watering
	FertCost = 25,      -- coins, per plot
	StartPlots = 4,     -- a starter parcel. The plot count is the throttle on
	MaxPlots = 12,      -- farm income -- see docs/FARMING.md section 5
	PlotCosts = { 300, 700, 1400, 2400, 4000, 6500, 10000, 15000 }, -- plots 5..12
	StartCarry = 10,    -- crops you can carry into town before upgrading
	StartStore = 50,    -- parcel storage
	Stages = 4,         -- growth stages drawn on a plot (0..3, 3 = ready)
}
function Config.Crop(id)
	for _, c in Config.Crops do
		if c.id == id then return c end
	end
	return nil
end

---------------------------------------------------------------------------
-- STARTER NEIGHBOURHOODS: one per role, and the flat you wake up in.
--
-- These are NOT Config.City.AptBuildings. Those five are the aspirational
-- places you save for; these are where everybody starts, free, before they
-- have earned anything. A tiny flat you outgrow is a better opening than a
-- free house, because it is what makes the house mean something later.
--
-- TEST SCAFFOLD, AND SAYING SO IN WRITING. `preset` is a Roblox inventory
-- model, which is exactly what .claude/rules/assets.md says production
-- geometry is not: it has unknown topology, scale and collision, and it did
-- not come out of art/blender. It is here to get the flow playable this
-- week. Every one of these is replaced by kit geometry before the slice
-- ships, and nothing else in the codebase may grow a dependency on the
-- preset's internal names.
---------------------------------------------------------------------------
Config.Hoods = {
	{ id = "meadow", name = "MEADOW LANE", role = "farmer",
		blurb = "The lane at the edge of the farm belt.",
		preset = 621745883, home = 4874260371, interior = 9461502368 },
	{ id = "motorrow", name = "MOTOR ROW", role = "driver",
		blurb = "Over the garages, east side.",
		preset = 621745883, home = 4874260371, interior = 9461502368 },
	{ id = "market", name = "MARKET SIDE", role = "cook",
		blurb = "Above the market, where the city eats.",
		preset = 621745883, home = 4874260371, interior = 9461502368 },
}
function Config.Hood(id)
	for _, h in Config.Hoods do
		if h.id == id then return h end
	end
	return nil
end

---------------------------------------------------------------------------
-- CITY TASKS: the answer to "what do I do?", and the reason onboarding does
-- not end. See docs/ONBOARDING.md section 5.
--
-- THE TUTORIAL IS JUST THE FIRST FEW ROWS OF THIS LIST. There is no separate
-- onboarding system to maintain and drift out of date: a brand new player and
-- somebody at minute 300 get the same affordance, and the only difference is
-- which row is at the top.
--
-- EVERY TASK CARRIES FOUR THINGS, and that is what makes it teach rather than
-- nag:
--   text    what to do
--   reward  what you get -- coins, and xp
--   how     the one line that says where or how, in plain words
--   track   where TRACK sends you (beacon + CityWayfind), or nil
--
-- Progress uses the SAME `stat` counters the daily challenges already
-- increment, so nothing new has to be tallied and a task cannot disagree with
-- a challenge about how many jobs you have done.
--
-- ORDER IS THE TEACHING ORDER. `after` names the task that must be complete
-- before this one is offered, so the opening sequence is a chain and
-- everything past it is open. Ids are saved, so they are append-only.
---------------------------------------------------------------------------
Config.Tasks = {
	-- the guided opening (docs/ONBOARDING.md section 4)
	{ id = "role", text = "Pick where to start", how = "Choose a role",
		reward = 0, xp = 5, stat = "roleSet", goal = 1 },
	{ id = "firstcoin", text = "Earn your first coin", how = "Tidy the litter on the pavement",
		reward = 0, xp = 5, stat = "sweeps", goal = 1, after = "role",
		track = { kind = "litter" } },
	{ id = "firstjob", text = "Work your first shift", how = "Your job is marked on the map",
		reward = 100, xp = 25, stat = "cityJobs", goal = 1, after = "firstcoin",
		track = { kind = "work" } },
	{ id = "firstbuy", text = "Spend some of it", how = "Clothes are the cheapest way to change how you look",
		reward = 0, xp = 15, stat = "cityBuys", goal = 1, after = "firstjob",
		track = { kind = "shop" } },
	{ id = "gohome", text = "Go and see where you live", how = "Your flat is marked on the map",
		reward = 50, xp = 15, stat = "homeVisits", goal = 1, after = "firstbuy",
		track = { kind = "home" } },
	{ id = "earn500", text = "Earn 500 coins", how = "Any job in the city counts",
		reward = 150, xp = 50, stat = "coins", goal = 500, after = "gohome" },

	-- open-ended, offered in any order once the opening is done
	{ id = "tryjob2", text = "Try a different job", how = "The Job Center lists every one",
		reward = 200, xp = 40, stat = "cityJobKinds", goal = 2, after = "earn500",
		track = { kind = "jobcentre" } },
	{ id = "buycar", text = "Buy your first vehicle", how = "Sminski Motors, east side",
		reward = 300, xp = 60, stat = "carsOwned", goal = 2, after = "earn500",
		track = { kind = "dealer" } },
	{ id = "movehouse", text = "Move somewhere better", how = "A flat of your own beats the starter room",
		reward = 300, xp = 60, stat = "aptsOwned", goal = 1, after = "earn500" },
}

-- The opening chain, in order -- the tasks that make up the guided first
-- fifteen minutes. Anything not in here is open-ended.
Config.TaskOpening = { "role", "firstcoin", "firstjob", "firstbuy", "gohome", "earn500" }

function Config.Task(id)
	for _, t in Config.Tasks do
		if t.id == id then return t end
	end
	return nil
end

-- IS THIS TASK AVAILABLE YET? A task with no `after` is always offered; one
-- with an `after` waits for that id to be in `done`.
function Config.TaskReady(task, done)
	if not task.after then return true end
	return (done or {})[task.after] == true
end

-- THE ONE THING TO DO NEXT, or nil when there is nothing left. The goal
-- widget shows this and it should never be empty while any task remains --
-- an empty widget is the "what do I do?" problem coming straight back.
function Config.NextTask(done, stats)
	done = done or {}
	stats = stats or {}
	for _, t in Config.Tasks do
		if not done[t.id] and Config.TaskReady(t, done) then
			return t, math.min(stats[t.stat] or 0, t.goal)
		end
	end
	return nil
end

-- WHAT IS IN THE STARTER FLAT. One room, and every object in it is a verb --
-- a room you can only look at teaches a new player that rooms are scenery.
-- No window in v1; the flat is small and interior-lit and does not need one.
--
-- THE COMPUTER IS THE IMPORTANT ONE. It is the phone's desk twin and the
-- in-fiction answer to "where do I find work": it shows the SAME task list
-- the phone does (docs/ONBOARDING.md section 5.2), so there is one task
-- system with two surfaces rather than two systems that drift.
Config.StarterHome = {
	{ id = "bed", name = "Bed", act = "sleep" },
	{ id = "closet", name = "Closet", act = "outfits" },
	{ id = "fridge", name = "Fridge", act = "eat" },
	{ id = "tv", name = "TV", act = "watch" },
	{ id = "computer", name = "Computer", act = "tasks" },
}

-- HOW FAR ALONG A PLOT IS, 0..1. The one place this arithmetic lives: the
-- server pays off it, the client draws off it, and neither may invent its
-- own. `now` is workspace:GetServerTimeNow() on both sides.
function Config.CropProgress(plot, now)
	local c = plot and plot.crop and Config.Crop(plot.crop)
	if not c or not plot.at then return 0 end
	local span = c.grow
	if plot.watered then span *= (1 - Config.Farm.WaterCut) end
	if plot.fert then span *= (1 - Config.Farm.FertCut) end
	return math.clamp((now - plot.at) / math.max(span, 1), 0, 1)
end

-- 0..Stages-1. Stage Stages-1 is ready, and a ready crop never leaves it.
function Config.CropStage(plot, now)
	local k = Config.CropProgress(plot, now)
	return math.min(Config.Farm.Stages - 1, math.floor(k * Config.Farm.Stages))
end

---------------------------------------------------------------------------
-- JOBS. The city already had work in it -- parcels, fares, litter, fields --
-- scattered across the map with no front door and no sense of a career. The
-- Job Center gives all of it one place to be found, one reputation to build,
-- and one shift to clock in and out of.
--
-- TWO KINDS OF JOB LIVE IN THIS TABLE, and the difference matters:
--
--   world = true   the job IS the open city. Taxi, deliveries, tidy-up and
--                  the fields already work this way: you clock in and the
--                  existing loop starts feeding you tasks wherever you are.
--                  Nothing new is built for these; the Job Center indexes
--                  them and layers pay, ELO and shifts on top.
--
--   room  = <id>   the job happens at a workplace with stations in it. The
--                  pizzeria is the first. Config.Restaurants holds its menu
--                  and recipes, and one framework runs all of them.
--
-- A job with `soon = true` is listed but cannot be started. That is
-- deliberate: the browser is meant to show the whole career ecosystem so a
-- player can see what they are working towards, and a job that is honestly
-- labelled "not open yet" is better than one that is hidden or one that
-- pretends.
--
-- PAY IS BALANCED AGAINST WHAT THE CITY ALREADY PAYS. A parcel run is
-- Delivery.base 30 + 1/8 a stud, so 70-110 coins for a few hundred studs of
-- walking; a fare is 75-125. `base` below is per TASK, before performance,
-- tips and ELO, and sits in that same band -- a job is a denser, more
-- interesting way to earn what the city already pays, not a new faucet.
---------------------------------------------------------------------------
Config.Jobs = {
	-- TRANSPORT ------------------------------------------------------------
	{ id = "taxi", name = "Taxi Driver", cat = "TRANSPORT", world = "taxi",
		place = "Downtown", elo = 0, hard = 2, base = 70, icon = "pin", color = Color3.fromRGB(245, 196, 80),
		blurb = "Pick fares up and get them across town. Drive well and they tip.",
		tasks = "fares", weight = 1, rank = { "Cabbie", "Licensed Driver", "Night Shift", "VIP Car", "Luxury Car" } },
	{ id = "delivery", name = "Delivery Driver", cat = "TRANSPORT", world = "delivery",
		place = "The Post Office", elo = 0, hard = 1, base = 55, icon = "bag", color = Color3.fromRGB(120, 180, 250),
		blurb = "Take parcels from the depot to doors all over the city.",
		tasks = "parcels", weight = 1, rank = { "Runner", "Courier", "Senior Courier", "Route Lead", "Depot Chief" } },
	{ id = "bus", name = "Bus Driver", cat = "TRANSPORT", soon = true,
		place = "Central Station", elo = 250, hard = 2, base = 80, icon = "play", color = Color3.fromRGB(150, 200, 130),
		blurb = "A fixed route, a timetable, and everyone waiting at the stop." },

	-- CITY SERVICES --------------------------------------------------------
	{ id = "cleaner", name = "City Cleaner", cat = "CITY SERVICES", world = "litter",
		place = "Anywhere on the streets", elo = 0, hard = 1, base = 40, icon = "coin", color = Color3.fromRGB(120, 200, 150),
		blurb = "The streets are the job. Clear litter wherever you find it.",
		tasks = "streets", weight = 0.12, rank = { "Helper", "Cleaner", "Senior Cleaner", "Sweeper Driver", "Depot Foreman" } },
	{ id = "farmhand", name = "Farm Hand", cat = "CITY SERVICES", world = "farm",
		place = "The farm belt, north", elo = 0, hard = 1, base = 45, icon = "star", color = Color3.fromRGB(170, 210, 110),
		blurb = "Plant the city fields, wait for them to ripen, bring the crop in.",
		tasks = "fields", weight = 0.25, rank = { "Picker", "Farm Hand", "Grower", "Field Lead", "Farm Manager" } },
	{ id = "police", name = "Police Officer", cat = "CITY SERVICES", soon = true,
		place = "Across the city", elo = 500, hard = 3, base = 160, icon = "star", color = Color3.fromRGB(110, 150, 230),
		blurb = "Patrol, answer call-outs, catch whoever is running." },
	{ id = "construction", name = "Construction Worker", cat = "CITY SERVICES", soon = true,
		place = "Sites around town", elo = 250, hard = 2, base = 120, icon = "bolt", color = Color3.fromRGB(250, 170, 60),
		blurb = "Carry, place, hammer. Sites finish and the building actually goes up." },
	{ id = "fire", name = "Firefighter", cat = "CITY SERVICES", soon = true,
		place = "The fire station", elo = 750, hard = 3, base = 180, icon = "heart", color = Color3.fromRGB(235, 90, 80),
		blurb = "Answer the bell, get there fast, put it out." },

	-- FOOD & RETAIL --------------------------------------------------------
	{ id = "pizzeria", name = "Pizzeria Cook", cat = "FOOD & RETAIL", room = "pizzeria",
		place = "Slice of Life, downtown", elo = 0, hard = 2, base = 60, icon = "heart", color = Color3.fromRGB(226, 100, 90),
		blurb = "Take the order, stretch the dough, sauce it, top it, bake it, cut it, box it, serve it.",
		tasks = "orders", rank = { "Kitchen Helper", "Cook", "Senior Cook", "Head Cook", "Chef" } },
	-- `base` on a `room` job is DISPLAY ONLY -- the server prices each order
	-- off Config.Restaurants[room].menu and never reads this. It is still set
	-- to the mean of that menu so the board's "X-Y a job" strip tells the
	-- truth: 60 for the bakery, 51 for the cafe, 54 for the burger bar.
	{ id = "bakery", name = "Baker", cat = "FOOD & RETAIL", room = "bakery",
		place = "The Little Bakery", elo = 100, hard = 2, base = 60, icon = "heart", color = Color3.fromRGB(236, 170, 110),
		blurb = "Mix it, shape it, fill it, bake it, ice it, box it. Everything goes out warm.",
		tasks = "orders", rank = { "Kitchen Helper", "Baker", "Senior Baker", "Pastry Chef", "Head Baker" } },
	{ id = "cafe", name = "Barista", cat = "FOOD & RETAIL", room = "cafe",
		place = "The Good Cup", elo = 100, hard = 1, base = 51, icon = "heart", color = Color3.fromRGB(150, 96, 70),
		blurb = "Grind it, pull the shot, steam the milk, get the order right.",
		tasks = "orders", rank = { "Trainee", "Barista", "Senior Barista", "Head Barista", "Coffee Master" } },
	{ id = "burger", name = "Grill Cook", cat = "FOOD & RETAIL", room = "burger",
		place = "Patty & Bun", elo = 250, hard = 2, base = 54, icon = "heart", color = Color3.fromRGB(240, 150, 80),
		blurb = "Buns toasted, patty on the flat top, build it, wrap it. It gets busy.",
		tasks = "orders", rank = { "Grill Trainee", "Grill Cook", "Senior Grill", "Line Lead", "Head Cook" } },
	{ id = "grocery", name = "Grocery Clerk", cat = "FOOD & RETAIL", soon = true,
		place = "The Supermarket", elo = 0, hard = 1, base = 45, icon = "bag", color = Color3.fromRGB(120, 200, 110),
		blurb = "Stock the shelves, work the till, find things for people." },

	-- SPECIALIZED ----------------------------------------------------------
	{ id = "mechanic", name = "Mechanic", cat = "SPECIALIZED", soon = true,
		place = "Sminski Motors", elo = 500, hard = 3, base = 140, icon = "gear", color = Color3.fromRGB(150, 160, 180),
		blurb = "Diagnose it, fix it, hand the keys back." },
	{ id = "photo", name = "Photographer", cat = "SPECIALIZED", soon = true,
		place = "Wherever the shot is", elo = 250, hard = 2, base = 100, icon = "star", color = Color3.fromRGB(190, 150, 250),
		blurb = "A brief, a location, and a shot to line up." },
}
Config.JobCats = { "TRANSPORT", "CITY SERVICES", "FOOD & RETAIL", "SPECIALIZED" }

function Config.Job(id)
	for _, j in Config.Jobs do
		if j.id == id then return j end
	end
	return nil
end

---------------------------------------------------------------------------
-- JOB REPUTATION (ELO). One number across every job: it says how reliable
-- you are at work, not how good you are at one task.
--
-- IT IS DELIBERATELY HARD TO WRECK. A perfect task is +7 and a completely
-- botched one is -6, so it takes a long run of bad shifts to fall a tier and
-- a single bad order costs you almost nothing. Nobody should feel their
-- career is over because they burnt a pizza.
---------------------------------------------------------------------------
Config.JobEloStart = 120
Config.JobEloResetCost = 1000
Config.JobRanks = {
	{ min = 0, name = "NEW" }, { min = 100, name = "BEGINNER" }, { min = 250, name = "RELIABLE" },
	{ min = 500, name = "EXPERIENCED" }, { min = 750, name = "PROFESSIONAL" }, { min = 1000, name = "EXPERT" },
}
function Config.JobRank(elo)
	local best = Config.JobRanks[1]
	for _, r in Config.JobRanks do
		if elo >= r.min then best = r end
	end
	return best.name
end
-- how far through the current tier, for a progress bar
function Config.JobRankProgress(elo)
	local lo, hi = 0, 1000
	for i, r in Config.JobRanks do
		if elo >= r.min then
			lo = r.min
			hi = Config.JobRanks[i + 1] and Config.JobRanks[i + 1].min or (r.min + 500)
		end
	end
	return math.clamp((elo - lo) / math.max(1, hi - lo), 0, 1), lo, hi
end
-- score is 0..1. Break-even is 0.6, so a merely OK task holds you steady.
function Config.JobEloDelta(score)
	return math.clamp(math.floor((score - 0.6) * 18 + 0.5), -6, 7)
end
-- what a career title is called at your reputation (five steps per job)
function Config.JobTitle(job, elo)
	if not job or not job.rank then return nil end
	local step = math.clamp(math.floor(elo / 250) + 1, 1, #job.rank)
	return job.rank[step]
end

---------------------------------------------------------------------------
-- WHAT A TASK PAYS. base -> performance -> tip -> reputation, in that order.
--
--   performance  up to +40% of base, straight-line with your score
--   tip          only above a 50% score, so a tip is earned rather than given
--   reputation   up to +25% at Expert -- enough to feel, small enough that a
--                new player is not locked out of a job by their own newness
--
-- Everything then goes through the server's pay(), which applies the CITY
-- PRO / VIP / 2x passes and any active boost on top, exactly like every
-- other city job.
---------------------------------------------------------------------------
function Config.JobPay(base, score, elo)
	base = math.max(1, math.floor(base))
	score = math.clamp(score or 0, 0, 1)
	local perf = math.floor(base * 0.4 * score)
	local tip = math.floor(base * 0.7 * math.max(0, score - 0.5))
	local mult = 1 + math.clamp(elo or 0, 0, 1200) / 1200 * 0.25
	local total = math.floor((base + perf + tip) * mult)
	return total, base, perf, tip, mult
end

-- STREAKS: a small nudge to keep going, never a punishment for stopping.
Config.JobStreaks = { { n = 3, pay = 25 }, { n = 5, pay = 60 }, { n = 10, pay = 150 }, { n = 20, pay = 400 } }
function Config.JobStreakBonus(n)
	for _, s in Config.JobStreaks do
		if s.n == n then return s.pay end
	end
	return 0
end

---------------------------------------------------------------------------
-- RESTAURANTS. One framework, many kitchens: a restaurant is a menu, a set
-- of stations and the order the stations run in. The pizzeria was the first
-- one built; the bakery, the cafe and the burger bar below are the same
-- shape with different stations and not one line of new code, which is the
-- whole reason this is a table.
--
-- `steps` is the pipeline for one order. Each entry names a station and the
-- minigame it runs. `weight` is how much that step counts towards the order
-- score, and they sum to 1.
--
-- FIVE KINDS OF STEP EXIST AND ONLY FIVE. CityKitchen dispatches on `kind`
-- through stop / fill / pick / bake / taps / serve, and an unknown kind
-- falls into the "stop" branch silently -- it does not error, it just quietly
-- gives you the wrong minigame. So a station is named by what the COOK does
-- (`station`), dressed by what it LOOKS like (`build`, read by CityBuild's
-- BENCH table) and played by one of the five (`kind`). The burger grill is
-- the worked example: kind = "bake", build = "grill".
--
-- `bench` is the wording on the name plate; without it CityBuild falls back
-- to the pizzeria's own labels, which are only right for the pizzeria. On a
-- `taps` step, `verb` is the word on the button for the same reason -- the
-- panel was written for cutting a pizza, and a button reading CUT while you
-- ice a cake is the game describing a different shop. Both default to the
-- pizzeria's wording, so a row that omits them is never broken, only vague.
--
-- THE INGREDIENT LIST MUST BE CALLED `toppings`, whatever the shop calls it
-- on the plate. CityKitchen reads `R.toppings` directly in two places (the
-- ticket roll and the pick tray), so renaming it to `syrups` would build a
-- rail of syrups the tray had never heard of. Say "SYRUPS" in `bench`.
--
-- PAY IS PER SECOND OF PAR, not per order. The server prices an order from
-- `menu[].pay` and then scales it by how long the order really took against
-- `par` (see the pace clamp in the job `task` handler), so the honest rate a
-- kitchen earns is mean(menu.pay) / par. The pizzeria sets that number:
-- 300/5 = 60 coins over a 42-second par = 1.43 base coins a second. Every
-- kitchen below is tuned to within 1% of it, so which restaurant you work at
-- is a question of taste and reputation and never of coins per minute.
--
-- `par` itself is ~7 seconds per station -- the pizzeria's 42 over six -- plus
-- a little where the tray is bigger or the pours are slower. It is also the
-- anti-script floor (an order faster than par/2 is refused outright), so it
-- is not a number to shave.
---------------------------------------------------------------------------
Config.Restaurants = {
	pizzeria = {
		id = "pizzeria", name = "SLICE OF LIFE", job = "pizzeria",
		blurb = "A proper little pizzeria. Eight seats, one oven, a queue out the door at lunch.",
		accent = Color3.fromRGB(226, 100, 90),
		-- what customers ask for; `n` is how many toppings the ticket names
		menu = {
			{ id = "margherita", name = "Margherita", n = 1, pay = 46 },
			{ id = "pepperoni", name = "Pepperoni", n = 1, pay = 52 },
			{ id = "veggie", name = "Garden", n = 2, pay = 60 },
			{ id = "meatfeast", name = "The Lot", n = 3, pay = 74 },
			{ id = "halfhalf", name = "Half & Half", n = 2, pay = 68, half = true },
		},
		toppings = {
			{ id = "cheese", name = "Cheese", color = Color3.fromRGB(250, 226, 150) },
			{ id = "pepperoni", name = "Pepperoni", color = Color3.fromRGB(214, 84, 74) },
			{ id = "mushroom", name = "Mushroom", color = Color3.fromRGB(214, 196, 170) },
			{ id = "pepper", name = "Peppers", color = Color3.fromRGB(120, 190, 110) },
			{ id = "olive", name = "Olives", color = Color3.fromRGB(78, 74, 96) },
			{ id = "onion", name = "Onion", color = Color3.fromRGB(240, 226, 240) },
		},
		steps = {
			{ station = "dough", kind = "stop", name = "STRETCH THE DOUGH", weight = 0.15,
				hint = "stop the roller in the middle" },
			{ station = "sauce", kind = "fill", name = "SPREAD THE SAUCE", weight = 0.15,
				hint = "hold to pour \u{00B7} stop in the band" },
			{ station = "top", kind = "pick", name = "ADD THE TOPPINGS", weight = 0.35,
				hint = "tap what the ticket asks for" },
			{ station = "oven", kind = "bake", name = "BAKE IT", weight = 0.2,
				hint = "pull it out when it is just right" },
			{ station = "cut", kind = "taps", name = "CUT IT", weight = 0.1, taps = 4,
				hint = "four clean cuts, in time" },
			{ station = "counter", kind = "serve", name = "BOX IT AND SERVE", weight = 0.05,
				hint = "take it to the customer" },
		},
		-- how long one order should take a competent cook, for the speed score
		par = 42,
	},

	bakery = {
		id = "bakery", name = "THE LITTLE BAKERY", job = "bakery",
		blurb = "Everything in the window was made this morning. The queue starts before the door is unlocked.",
		accent = Color3.fromRGB(236, 170, 110),
		-- six stations, so par matches the pizzeria's 42. Mean pay 240/4 = 60,
		-- which is the pizzeria's mean exactly: same rate, different hands.
		menu = {
			{ id = "melonpan", name = "Melon Pan", n = 1, pay = 46 },
			{ id = "creampuff", name = "Cream Puff", n = 1, pay = 52 },
			{ id = "fruittart", name = "Fruit Tart", n = 2, pay = 62 },
			{ id = "cake", name = "Celebration Cake", n = 3, pay = 80 },
		},
		toppings = {
			{ id = "cream", name = "Cream", color = Color3.fromRGB(250, 240, 224) },
			{ id = "berries", name = "Berries", color = Color3.fromRGB(198, 74, 108) },
			{ id = "chocolate", name = "Chocolate", color = Color3.fromRGB(120, 78, 58) },
			{ id = "lemon", name = "Lemon", color = Color3.fromRGB(250, 226, 130) },
			{ id = "pistachio", name = "Pistachio", color = Color3.fromRGB(160, 200, 130) },
		},
		steps = {
			{ station = "mix", kind = "fill", name = "MIX THE BATTER", weight = 0.15,
				bench = "MIX", color = Color3.fromRGB(244, 226, 180),
				hint = "hold to pour \u{00B7} stop in the band" },
			{ station = "shape", kind = "stop", name = "SHAPE IT", weight = 0.15,
				bench = "SHAPE", hint = "stop the roller in the middle" },
			{ station = "top", kind = "pick", name = "FILL IT", weight = 0.3,
				bench = "FILLINGS", hint = "tap what the ticket asks for" },
			{ station = "oven", kind = "bake", name = "BAKE IT", weight = 0.25,
				hint = "pull it out when it is just right" },
			{ station = "cut", kind = "taps", name = "ICE IT AND BOX IT", weight = 0.1, taps = 4,
				bench = "ICE & BOX", verb = "ICE", hint = "four passes of the icing, in time" },
			{ station = "counter", kind = "serve", name = "BOX IT AND SERVE", weight = 0.05,
				hint = "take it to the customer" },
		},
		par = 42,
	},

	cafe = {
		id = "cafe", name = "THE GOOD CUP", job = "cafe",
		blurb = "One machine, one grinder and a regular in every seat. Nobody is in a hurry except the queue.",
		accent = Color3.fromRGB(150, 96, 70),
		-- five stations (35) plus a second for the two slow pours = par 36.
		-- Mean pay 204/4 = 51; 51/36 = 1.417 a second, 99.2% of the pizzeria.
		-- Espresso is the only n = 0 ticket in town: "just as it comes".
		menu = {
			{ id = "espresso", name = "Espresso", n = 0, pay = 40 },
			{ id = "flatwhite", name = "Flat White", n = 1, pay = 48 },
			{ id = "matchalatte", name = "Matcha Latte", n = 1, pay = 52 },
			{ id = "mocha", name = "Mocha", n = 2, pay = 64 },
		},
		toppings = {
			{ id = "milk", name = "Milk", color = Color3.fromRGB(248, 242, 230) },
			{ id = "cocoa", name = "Cocoa", color = Color3.fromRGB(110, 74, 58) },
			{ id = "matcha", name = "Matcha", color = Color3.fromRGB(140, 190, 120) },
			{ id = "caramel", name = "Caramel", color = Color3.fromRGB(216, 154, 84) },
			{ id = "cinnamon", name = "Cinnamon", color = Color3.fromRGB(196, 140, 96) },
		},
		steps = {
			{ station = "grind", kind = "stop", name = "GRIND THE BEANS", weight = 0.2,
				bench = "GRIND", hint = "stop the grinder on the dose" },
			{ station = "brew", kind = "fill", name = "PULL THE SHOT", weight = 0.25,
				bench = "THE MACHINE", color = Color3.fromRGB(96, 62, 44),
				hint = "hold to pour \u{00B7} stop in the band" },
			{ station = "steam", kind = "fill", name = "STEAM THE MILK", weight = 0.25,
				bench = "STEAM", color = Color3.fromRGB(244, 240, 232),
				hint = "hold to steam \u{00B7} stop in the band" },
			{ station = "top", kind = "pick", name = "FINISH THE CUP", weight = 0.25,
				bench = "SYRUPS", hint = "tap what the ticket asks for" },
			{ station = "counter", kind = "serve", name = "CALL IT AND SERVE", weight = 0.05,
				hint = "take it to the customer" },
		},
		par = 36,
	},

	burger = {
		id = "burger", name = "PATTY & BUN", job = "burger",
		blurb = "A flat top, a six-tub rail and a lunch rush that does not let up. Loud, hot, and the best tips in town.",
		accent = Color3.fromRGB(240, 150, 80),
		-- five stations (35) plus three for the six-tub rail and n = 3 tickets
		-- = par 38. Mean pay 216/4 = 54; 54/38 = 1.421 a second, 99.5% of the
		-- pizzeria. Highest tips because the tickets are the longest to read,
		-- not because the till is deeper.
		menu = {
			{ id = "classic", name = "The Classic", n = 1, pay = 44 },
			{ id = "doublecheese", name = "Double Cheese", n = 2, pay = 52 },
			{ id = "garden", name = "Garden Burger", n = 2, pay = 54 },
			{ id = "bigstack", name = "The Big Stack", n = 3, pay = 66 },
		},
		toppings = {
			{ id = "cheese", name = "Cheese", color = Color3.fromRGB(250, 208, 108) },
			{ id = "lettuce", name = "Lettuce", color = Color3.fromRGB(130, 196, 110) },
			{ id = "tomato", name = "Tomato", color = Color3.fromRGB(220, 86, 76) },
			{ id = "pickles", name = "Pickles", color = Color3.fromRGB(160, 186, 96) },
			{ id = "onion", name = "Onion", color = Color3.fromRGB(240, 226, 240) },
			{ id = "sauce", name = "Burger Sauce", color = Color3.fromRGB(238, 160, 120) },
		},
		steps = {
			{ station = "dough", kind = "stop", name = "TOAST THE BUNS", weight = 0.15,
				bench = "BUNS", hint = "stop the toaster in the middle" },
			-- THE GRILL. `kind` is "bake" because that is the only timed-window
			-- minigame CityKitchen has, and it is exactly the right one: a slow
			-- marker, a good band, and a patty that is ruined if you leave it.
			-- `build` is "grill" so the room still gets a flat top with a hood
			-- and not a brick pizza arch. Do not "fix" this to kind = "grill" --
			-- there is no such kind, and it would silently become a plain stop.
			{ station = "oven", kind = "bake", build = "grill", name = "ON THE GRILL", weight = 0.3,
				bench = "THE GRILL", hint = "take it off when it is just right" },
			{ station = "top", kind = "pick", name = "BUILD THE BURGER", weight = 0.35,
				bench = "BUILD IT", hint = "tap what the ticket asks for" },
			{ station = "cut", kind = "taps", name = "WRAP IT AND BOX IT", weight = 0.15, taps = 3,
				bench = "WRAP & BOX", verb = "WRAP", hint = "three folds, in time" },
			{ station = "counter", kind = "serve", name = "ON THE PASS", weight = 0.05,
				hint = "take it to the customer" },
		},
		par = 38,
	},
}
function Config.Restaurant(id) return Config.Restaurants[id] end

---------------------------------------------------------------------------
-- CITY EVENTS: the short loops. See docs/LOOPS.md.
--
-- Everything else in the city is private -- your litter, your fare, your
-- parcel. These are the first things that happen to THE SERVER, so two
-- players on the same street finally have the same thing to run towards.
--
-- An event is DATA. The server's director and the client's CityEvents module
-- only know the archetypes (`kind`); adding an event of a kind that exists is
-- a row in this list and nothing else.
--
--   kind = "find"   one thing at one spot. Hidden unless `open`.
--     open      the spot is announced (a truck you race to) rather than hunted
--     ambient   never scheduled as a headline; slips in between them
--     warn      seconds of notice before it starts (time to travel)
--     lasts     seconds it stays
--     clues     when each clue unlocks, in seconds after the start
--     coins/xp  what finding it pays; `first` is the extra for getting there first
--     firstN    how many early arrivals share the `first` bonus (default 1)
--
--   kind = "collect"  N things scattered across a public zone. The zone is
--     never a secret -- everyone is meant to converge on it -- and each item
--     is taken exactly once, by whoever reaches it first.
--     shared    true  = one goal the whole city fills together (cooperative)
--               false = first come, first served (competitive)
--     count     competitive: how many items are dropped
--     base/per/maxCount  cooperative: the goal scales with how many players
--               are in the city -- goal = clamp(base + per*(n-1), base, maxCount)
--     each/xp   what ONE item pays
--     bonusAt/bonus/bonusXp  the completion bonus, paid once at the finish to
--               everyone who collected at least `bonusAt` of them
--     noun/verb the words the strip and the phone use
--     credits   a world job id each item also credits (see creditWorld): the
--               work counts for a shift without paying twice
--     minPlayers  the director will not schedule it below this many players
--               in the city (a prize pool "split across the server" needs one)
--
-- THE MONEY IS DELIBERATELY ORDINARY. A paced job earns ~187 coins a minute;
-- an event pays about that for the minutes it takes, travel included. The
-- draw is novelty, the collectible and the other players -- if events ever
-- out-earn working, nobody works.
---------------------------------------------------------------------------
Config.Events = {
	FirstAfter = 50,            -- seconds after the server starts before the first headline
	Gap = { 150, 210 },         -- seconds from one headline ending to the next being announced
	AmbientGap = { 70, 130 },   -- the same, for ambient sightings
	RevealRadius = 130,         -- a hidden thing's position is only sent to players this close
	ClaimRadius = 16,
	List = {
		{ id = "sighting", kind = "find", ambient = true, title = "SMINSKI SIGHTING", icon = "star",
			lasts = 110, newsAfter = 25, afterFound = 60, xp = 20, first = 80, verb = "SAY HI" },
		{ id = "lostpup", kind = "find", title = "LOST PUP", icon = "paw", weight = 10,
			warn = 20, lasts = 240, clues = { 0, 45, 100 }, coins = 260, xp = 30, first = 200, verb = "RESCUE" },
		{ id = "icecream", kind = "find", open = true, title = "ICE CREAM TRUCK", icon = "heart", weight = 10,
			warn = 50, lasts = 170, coins = 200, xp = 25, first = 120, firstN = 3, verb = "ORDER" },

		-- COLLECT (phase B). Appended -- the three rows above are phase A and
		-- must not change; saved data indexes nothing here, but the director's
		-- "not the last few headlines" memory is sized from this list.
		{ id = "cashdrop", kind = "collect", open = true, shared = false,
			title = "CASH DROP!", icon = "coin", noun = "bags", verb = "GRAB",
			warn = 45, lasts = 150, weight = 10, minPlayers = 2,
			count = 24, each = 60, xp = 3 },

		{ id = "balloons", kind = "collect", open = true, shared = true,
			title = "BALLOON FESTIVAL", icon = "heart", noun = "balloons", verb = "POP",
			warn = 45, lasts = 180, weight = 10, minPlayers = 1,
			base = 12, per = 8, maxCount = 48, each = 8, xp = 2,
			bonusAt = 3, bonus = 220, bonusXp = 20 },

		{ id = "cleanup", kind = "collect", open = true, shared = true,
			title = "CITY CLEANUP", icon = "bag", noun = "litter", verb = "BIN",
			warn = 45, lasts = 180, weight = 10, minPlayers = 1,
			base = 12, per = 8, maxCount = 48, each = 8, xp = 2,
			bonusAt = 3, bonus = 220, bonusXp = 20, credits = "cleaner" },
	},
	-- A sighting is an NPC in one of the whole-body skins, so the rarity table
	-- is the skin catalogue bucketed by price: no new art, and the rarest
	-- sightings are the costumes players already covet.
	Tiers = {
		{ id = "common", name = "Common", weight = 60, under = 1000, coins = 100 },
		{ id = "uncommon", name = "Uncommon", weight = 28, under = 1500, coins = 180 },
		{ id = "rare", name = "Rare", weight = 10, under = 2000, coins = 320 },
		{ id = "legendary", name = "Legendary", weight = 2, under = math.huge, coins = 800 },
	},

	-----------------------------------------------------------------------
	-- COLLECT geometry (phase B). Appended; nothing above is affected.
	--
	-- The server cannot raycast -- the city is built on the client -- so a
	-- scattered item has to be clear BY CONSTRUCTION. Items sit +2 studs out
	-- from a lot's door line, the one strip that measured 0/105 blocked with
	-- open sky above it (docs/HANDOFF.md section 5), four to a lot, and only
	-- on lots that pass the director's street-section filter.
	-----------------------------------------------------------------------
	PickupRadius = 6,     -- the client auto-claims inside this
	PickupServer = 9,     -- the server validates at this, to absorb latency + streaming
	Zone = 170,           -- scatter radius from the centre lot
	SlotsPerLot = 4,      -- offsets along the frontage: -12, -4, +4, +12
	MinCentreLots = 12,   -- a lot is only a zone centre if this many eligible
	                      -- lots are within Zone of it: 12 x 4 slots = 48,
	                      -- which is the largest count any event asks for
}
function Config.Event(id)
	for _, e in Config.Events.List do
		if e.id == id then return e end
	end
	return nil
end
function Config.SightingTier(skin)
	for _, t in Config.Events.Tiers do
		if (skin.price or 0) < t.under then return t end
	end
	return Config.Events.Tiers[#Config.Events.Tiers]
end

---------------------------------------------------------------------------
-- THE CAPSULE TICKET METER  (short loops, phase D)
--
-- Every coin you EARN by doing something also fills a meter, one unit per
-- BASE coin, with a hard ceiling of PerMin units a rolling minute. So the
-- fastest possible ticket takes exactly ten minutes, and the best way to
-- farm tickets is to work a normal job.
--
-- Rates is a WHITELIST. A stat tag that is absent credits ZERO -- including
-- every stat tag added after this was written, which is the failure mode you
-- want. BizCollects (idle business income, two call sites), HomeNaps (a
-- once-per-20h gift) and the claw's untagged payout are deliberately absent:
-- a machine that hands out capsules must not fill the capsule meter. The
-- Endless Run is excluded for free, because award() never calls pay().
--
-- PASS-NEUTRALITY, PRECISELY. The meter is credited from the amount BEFORE
-- pay() applies CITY PRO / VIP / 2x COINS / the login streak, so the coin
-- multipliers change nothing here. The CEILING is pass-proof; the FLOOR is
-- not -- QUICK FEET and DREAM GARAGE fit more work into a minute, which
-- moves sweeping up to 2.1x and taxi and parcels 0x, because those two
-- already saturate 187/min on the free convertible. Nobody beats ten
-- minutes, and that is the point of expressing the ceiling in units/minute.
---------------------------------------------------------------------------
Config.Meter = {
	Ticket       = 1870, -- units for one ticket = 10 x PerMin, so the constant
	                     -- documents itself: ten minutes at the reference rate
	PerMin       = 187,  -- the ceiling: max units credited per rolling minute,
	                     -- set to LOOPS.md section 6's reference job rate
	Burst        = 187,  -- max bankable allowance = one minute's worth, so a
	                     -- single fat payout (a 363-coin fare) counts in full
	MaxTickets   = 4,    -- banked, unredeemed. The METER stops granting here;
	                     -- the Daily 3 grants anyway, so c.tickets may go past
	                     -- it. Never clamp c.tickets -- see the invariant in
	                     -- docs/specs/daily-capsule/loop.md D5.
	DayCap       = 12,   -- tickets GRANTED per UTC day, both sources. 120
	                     -- ceiling-rate minutes: a circuit breaker on a
	                     -- scripted account, not a brake on a real session.
	Redeem       = 14,   -- studs: the client prompt radius at Capsule Corner
	                     -- (matches the existing prompt, City.lua:2237)
	RedeemServer = 18,   -- studs: the server check, wider for latency and
	                     -- streaming. Same pattern as PickupRadius 6 / 9.
	Version      = 1,    -- unit-scale version. On mismatch: clear `meter`,
	                     -- KEEP `tickets`. Losing partial progress on a retune
	                     -- is acceptable; losing a banked ticket is not.
	Rates = {
		Deliveries = 1, TaxiFares = 1, Sweeps = 1, CityHarvests = 1,
		JobTasks   = 1, EventsDone = 1, Races  = 1, Hunt         = 1,
		-- serving at your own restaurant is work done with your thumbs, paced
		-- like a job (docs/TYCOON.md); the till you collect from it is not
		TycoonServes = 1,
		-- DELIBERATELY ABSENT, do not add: BizCollects, HomeNaps, the claw
		-- (stat = nil), TycoonCollects, and anything the Endless Run pays.
	},
}

---------------------------------------------------------------------------
-- THE DAILY 3 HUNT  (short loops, phase D)
--
-- Three hidden Sminski, their lots seeded from the UTC date, so they are the
-- SAME THREE on every server and survive a restart with no persistence at
-- all. Not events: nothing here is appended to Config.Events.List, they have
-- no uid, no endT and never enter the countdown strip or the headline memory.
--
-- Clue tiers are a function of progress -- yours and the server's -- never of
-- a timer, which is what makes standing near other players materially
-- useful. The tier NUMBER is derivable by anyone; the SENTENCE is not, and
-- the server only ever sends the text that has been earned.
---------------------------------------------------------------------------
Config.Hunt = {
	Count      = 3,
	Spread     = 500,   -- min studs between any two of today's spots. Forces a
	                    -- real trip across town; > one block + road (300).
	Reveal     = 90,    -- the position is only sent to players this close.
	                    -- Tighter than a sighting's 130 on purpose: it is
	                    -- small and hidden, not parked.
	Claim      = 12,    -- claim radius. At 16 you could claim from the door
	                    -- without ever spotting it.
	Scale      = 0.5,   -- buildSminski scale, distinct from a sighting's 1.0
	Skin       = "none",-- the plain body, so it is never mistaken for one
	Icon       = "capsule",
	Rewards    = { 60, 90, 150 },  -- BASE coins for the 1st / 2nd / 3rd find
	Xp         = { 15, 20, 60 },
	FirstHere  = 40,    -- extra BASE coins for the first finder of a spot on
	                    -- this server today
	TicketAt   = 3,     -- which find grants the capsule ticket
	StreakDays = 7,     -- consecutive 3/3 days for a second ticket
	Retries    = 6,     -- pickSpot() attempts before it accepts a hunt lot.
	                    -- 3 lots in ~381, so the retry runs under 1% of the
	                    -- time and can never spin.
	ExcludeR   = 24,    -- studs from a lot's DOOR to a blocking prompt before
	                    -- the lot leaves the candidate pool. 11.3 (the largest
	                    -- spot offset from the door) + 7 (a station lift's
	                    -- prompt radius) + margin. See the server's D1 block.
}
-- loop.md N2 named this list `Coins`; the contract named it `Rewards`. Same
-- table, both names, so neither spec sends a reader looking for a nil.
Config.Hunt.Coins = Config.Hunt.Rewards

---------------------------------------------------------------------------
-- GROCERIES. Things you buy in a store, carry to the till in a basket, pay
-- for with coins and take home to your fridge -- where a snack is worth a
-- little XP. Prices are pocket money on purpose: a paced job pays ~187 a
-- minute, so a whole basket is a minute's work. The store is a place to be,
-- not a sink. `mesh` names a curated farm-pack mesh that stands on the shelf
-- as the item itself; the rest sit on the store's textured shelves.
---------------------------------------------------------------------------
Config.Groceries = {
	{ id = "apple",      name = "Apples",       price = 12, mesh = "Food_4", col = Color3.fromRGB(226, 90, 80) },
	{ id = "tomato",     name = "Tomatoes",     price = 10, mesh = "Food_6", col = Color3.fromRGB(230, 70, 60) },
	{ id = "carrot",     name = "Carrots",      price = 8,  mesh = "Food_7", col = Color3.fromRGB(240, 140, 60) },
	{ id = "lettuce",    name = "Lettuce",      price = 9,  mesh = "Food_8", col = Color3.fromRGB(150, 200, 90) },
	{ id = "corn",       name = "Sweetcorn",    price = 11, mesh = "Food_3", col = Color3.fromRGB(250, 214, 80) },
	{ id = "watermelon", name = "Watermelon",   price = 24, mesh = "Food_2", col = Color3.fromRGB(80, 170, 90) },
	{ id = "pumpkin",    name = "Pumpkin",      price = 22, mesh = "Food_1", col = Color3.fromRGB(240, 150, 60) },
	{ id = "milk",       name = "Strawberry Milk", price = 14, col = Color3.fromRGB(255, 180, 200) },
	{ id = "bread",      name = "Melon Bread",  price = 15, col = Color3.fromRGB(236, 200, 130) },
	{ id = "eggs",       name = "Eggs",         price = 18, col = Color3.fromRGB(250, 240, 220) },
	{ id = "cereal",     name = "Star Cereal",  price = 22, col = Color3.fromRGB(255, 214, 90) },
	{ id = "cookies",    name = "Cookies",      price = 25, col = Color3.fromRGB(200, 140, 90) },
	{ id = "juice",      name = "Peach Juice",  price = 16, col = Color3.fromRGB(255, 176, 130) },
	{ id = "noodles",    name = "Cup Noodles",  price = 13, col = Color3.fromRGB(240, 120, 100) },
	{ id = "pudding",    name = "Pudding Cups", price = 20, col = Color3.fromRGB(255, 230, 150) },
	{ id = "cake",       name = "Birthday Cake", price = 45, col = Color3.fromRGB(255, 150, 190) },
}
Config.BasketMax = 12      -- items in one basket
Config.PantryMax = 30      -- items your fridge holds
Config.SnackXP = 15        -- eating from your own fridge
function Config.Grocery(id)
	for _, g in Config.Groceries do
		if g.id == id then return g end
	end
	return nil
end

---------------------------------------------------------------------------
-- RESTAURANT ROW: the tycoon. See docs/TYCOON.md.
--
-- A player claims a LOT, buys PIECES off build pads (the classic tycoon
-- vocabulary -- a pad with a price, a thing that appears when you pay), and
-- the restaurant sells the dishes its pieces unlock. Three ways coins come
-- out of it, and they are deliberately different kinds of money:
--
--   PASSIVE   it sells while you are away, like a shop in the Mall -- but
--             only while the STOCKROOM has ingredients. Every dish is a
--             recipe over Config.Groceries, so the grocery loop feeds this
--             one: fill the stockroom from the supplier (bulk price) or
--             carry your own fridge in. Banks like a business (CapMinutes,
--             the shift bonus, the TYCOON and AUTO-COLLECT passes).
--   SERVE     you at your own pass, a customer waiting, two quick steps on
--             the kitchen panel. Paced and paid like a job (Meter credits
--             it), so it is never a better faucet than working.
--   FRIENDS   another player ORDERS at your counter and pays the menu price
--             out of their own wallet into your till. Zero-sum: no coins
--             are minted, the city just moves them between friends.
--
-- Balance: a fully built restaurant sells ~130 coins/min of dishes whose
-- ingredients cost ~40% of that, so ~75/min net at full stock -- the Pizza
-- Place (18,000 -> 60/min) with a chore attached and a social loop on top.
-- Every rate below is SALES per minute; the margin is what the pieces earn.
---------------------------------------------------------------------------
Config.Tycoon = {
	-- THE PLOT, in plot-local studs: x to the right as you face the building
	-- from the street, z positive into the block (the back), negative toward
	-- the kerb. The plot is LotW x LotD; the building stands on x -22..14,
	-- z -10..19; the build pads run down the right-hand strip. Places.
	-- tycoonLots() turns these into city positions the server checks against.
	LotW = 44, LotD = 38,
	Along = { -56, 0, 56 },     -- three plots a side, twelve a block
	Blocks = { "750,750" },     -- which blocks are Restaurant Row (60 lots = 5)
	Spots = {
		gate  = { 18, -17 },     -- the claim gate, kerbside by the pads
		pads  = { { 18, -12 }, { 18, -7 }, { 18, -2 }, { 18, 3 }, { 18, 8 } },
		door  = { 2, -10 },
		queue = { 5, 6 },        -- where a customer stands; SERVE happens here
		till  = { 12, 6 },       -- the register: COLLECT
		tips  = { -1, 6 },       -- the tip jar
		stock = { -17, 13 },     -- the stockroom: RESTOCK / UNLOAD
		sign  = { -21, -17 },    -- the pylon sign, front-left corner
	},
	Reach = 34,                 -- studs from the plot centre = "at this restaurant"
	SpotRadius = 6,             -- studs from a spot to get its prompt
	ClaimRadius = 10,
	-- THE STOCKROOM
	StockMax = 120, StockroomMax = 300,
	Crate = 10, CrateDiscount = 0.8,  -- the supplier sells tens at 80% of shelf price
	-- SERVING, the active loop. A serve is refused inside ServeGap seconds of
	-- the last (two panel steps take ~14s honestly), and pays
	-- price x (ServePay[1] + ServePay[2] x score): 65 coins per 20s at a
	-- perfect score is 195/min -- job money, not shop money.
	ServeGap = 10, ServePay = { 0.5, 0.5 }, ServeXP = 8,
	CustomerEvery = { 18, 36 }, CustomerWaits = 60,
	Tip = 25, DineXPPerCoin = 0.5,
	-- STARS. Earned by serving and by friends ordering; passive sales earn
	-- none (or a restaurant would rate itself up while nobody was there).
	Stars = { 0, 40, 120, 300, 700 }, StarRate = 0.05,  -- +5% sales a star
	StarXP = { serve = 2, order = 3 },
	-- CHAINS. Another location across town, run for you: +25% sales each.
	Chain = { base = 15000, step = 10000, max = 3, rate = 0.25, minStars = 3, minPieces = 8 },
	-- THE BUILD TREE. `needs` gates the pad; at most five pads are ever
	-- available at once, which is how many pad slots the strip has.
	-- `model` names an Inventory template the piece stands as when it exists
	-- (the owner's curated kit pieces); the part-built fallback is drawn
	-- otherwise. `rate` = sales/min added while stocked.
	Pieces = {
		{ id = "doors",     name = "Open the Doors",  price = 0,    rate = 0,  blurb = "Floor, walls, a door and a menu board. Everything starts here." },
		{ id = "counter",   name = "The Counter",     price = 250,  rate = 6,  needs = "doors",   blurb = "A pass, a register and a little fridge. Your first three dishes." },
		{ id = "sign",      name = "The Sign",        price = 600,  rate = 6,  needs = "doors",   blurb = "Your name in lights on the kerb. People wander in." },
		{ id = "stockroom", name = "Stockroom",       price = 400,  rate = 0,  needs = "counter", blurb = "The stockroom holds 300 instead of 120." },
		{ id = "tables1",   name = "Four Seats",      price = 500,  rate = 6,  needs = "counter", seats = 4, blurb = "Two tables by the window." },
		{ id = "grill",     name = "The Grill",       price = 900,  rate = 10, needs = "counter", model = "Tyc_Stove", blurb = "Egg sandwiches and corn chowder." },
		{ id = "drinks",    name = "Drinks Machine",  price = 2000, rate = 10, needs = "counter", model = "Tyc_Soda",  blurb = "Peach fizz and cookie shakes." },
		{ id = "tables2",   name = "Eight Seats",     price = 1400, rate = 6,  needs = "tables1", seats = 4, blurb = "Two more tables. It is getting busy." },
		{ id = "oven",      name = "The Oven",        price = 2400, rate = 12, needs = "grill",   model = "Tyc_Oven",  blurb = "Melon toast and pumpkin pie." },
		{ id = "terrace",   name = "The Terrace",     price = 3200, rate = 10, needs = "tables2", seats = 6, blurb = "Three tables out front under parasols." },
		{ id = "fryer",     name = "The Fryer",       price = 4000, rate = 14, needs = "oven",    model = "Tyc_Fryer", blurb = "Noodle bowls and carrot fries." },
		{ id = "dessert",   name = "Dessert Bar",     price = 4800, rate = 14, needs = "drinks",  blurb = "Cake by the slice and pudding parfaits." },
		{ id = "drivethru", name = "Drive-Thru",      price = 6500, rate = 20, needs = "terrace", blurb = "A window on the side street. Cars queue for it." },
		{ id = "chef",      name = "Head Chef",       price = 9500, rate = 24, needs = "fryer",   blurb = "A chef at the pass all day. Everything sells faster." },
	},
	-- THE RECIPE BOOK. Every restaurant on the Row cooks from the same book;
	-- what YOURS can make is whichever `unlock` pieces you own. Prices sit at
	-- about 1.7x the shelf price of the ingredients, rounded to a fiver.
	-- `steps` are the SERVE minigame: two of CityKitchen's step kinds, then
	-- the hand-over. Only stop / fill / bake / taps here -- `pick` needs a
	-- toppings tray this book does not have.
	Menu = {
		{ id = "fruitcup",  name = "Fruit Cup",        price = 60, unlock = "counter", needs = { "apple", "watermelon" },
			steps = { { kind = "taps", name = "CHOP THE FRUIT", taps = 3, verb = "CHOP", hint = "three cuts, in time" } } },
		{ id = "salad",     name = "Garden Salad",     price = 50, unlock = "counter", needs = { "lettuce", "tomato", "corn" },
			steps = { { kind = "stop", name = "TOSS THE SALAD", hint = "stop the bowl in the middle" } } },
		{ id = "cerealbowl", name = "Star Cereal Bowl", price = 60, unlock = "counter", needs = { "cereal", "milk" },
			steps = { { kind = "fill", name = "POUR THE MILK", hint = "hold to pour \u{00B7} stop in the band" } } },
		{ id = "eggsando",  name = "Egg Sandwich",     price = 55, unlock = "grill", needs = { "bread", "eggs" },
			steps = { { kind = "stop", name = "CRACK THE EGGS", hint = "stop the pan in the middle" }, { kind = "bake", name = "ON THE GRILL", hint = "take it off when it is just right" } } },
		{ id = "chowder",   name = "Corn Chowder",     price = 45, unlock = "grill", needs = { "corn", "milk" },
			steps = { { kind = "fill", name = "POUR THE CREAM", hint = "hold to pour \u{00B7} stop in the band" }, { kind = "bake", name = "SIMMER IT", hint = "off the heat when it is just right" } } },
		{ id = "toast",     name = "Melon Toast",      price = 45, unlock = "oven", needs = { "bread", "apple" },
			steps = { { kind = "taps", name = "SLICE IT", taps = 3, verb = "SLICE", hint = "three slices, in time" }, { kind = "bake", name = "IN THE OVEN", hint = "pull it out when it is golden" } } },
		{ id = "pie",       name = "Pumpkin Pie",      price = 70, unlock = "oven", needs = { "pumpkin", "eggs" },
			steps = { { kind = "fill", name = "FILL THE CRUST", hint = "hold to pour \u{00B7} stop in the band" }, { kind = "bake", name = "BAKE IT", hint = "pull it out when it is just right" } } },
		{ id = "fizz",      name = "Peach Fizz",       price = 30, unlock = "drinks", needs = { "juice" },
			steps = { { kind = "fill", name = "POUR THE FIZZ", hint = "hold to pour \u{00B7} stop in the band" } } },
		{ id = "shake",     name = "Cookie Shake",     price = 65, unlock = "drinks", needs = { "milk", "cookies" },
			steps = { { kind = "taps", name = "CRUSH THE COOKIES", taps = 4, verb = "CRUSH", hint = "four taps, in time" }, { kind = "stop", name = "BLEND IT", hint = "stop the blender in the middle" } } },
		{ id = "noodles",   name = "Noodle Bowl",      price = 65, unlock = "fryer", needs = { "noodles", "eggs", "carrot" },
			steps = { { kind = "bake", name = "BOIL THE NOODLES", hint = "drain them when they are just right" }, { kind = "taps", name = "TOP IT", taps = 3, verb = "TOP", hint = "egg, carrot, spring onion" } } },
		{ id = "fries",     name = "Carrot Fries",     price = 35, unlock = "fryer", needs = { "carrot", "corn" },
			steps = { { kind = "taps", name = "CUT THE CARROTS", taps = 4, verb = "CUT", hint = "four cuts, in time" }, { kind = "bake", name = "IN THE FRYER", hint = "lift them when they are crisp" } } },
		{ id = "cakeslice", name = "Cake Slice",       price = 75, unlock = "dessert", needs = { "cake" },
			steps = { { kind = "taps", name = "CUT A SLICE", taps = 2, verb = "CUT", hint = "two clean cuts" } } },
		{ id = "parfait",   name = "Pudding Parfait",  price = 75, unlock = "dessert", needs = { "pudding", "cookies" },
			steps = { { kind = "fill", name = "LAYER IT", hint = "hold to pour \u{00B7} stop in the band" }, { kind = "stop", name = "CROWN IT", hint = "stop the swirl in the middle" } } },
	},
}
function Config.TycoonPiece(id)
	for _, p in Config.Tycoon.Pieces do
		if p.id == id then return p end
	end
	return nil
end
function Config.TycoonDish(id)
	for _, m in Config.Tycoon.Menu do
		if m.id == id then return m end
	end
	return nil
end
-- how many stars a restaurant with this much star-xp has (1..5)
function Config.TycoonStars(xp)
	local n = 1
	for i, need in Config.Tycoon.Stars do
		if xp >= need then n = i end
	end
	return n
end
-- what a set of owned pieces sells per minute, before stars and chains
function Config.TycoonBaseRate(pieces)
	local r = 0
	for _, p in Config.Tycoon.Pieces do
		if pieces[p.id] then r += p.rate end
	end
	return r
end
-- the pieces whose pad should be standing: not owned, dependency owned
function Config.TycoonAvailable(pieces)
	local out = {}
	for _, p in Config.Tycoon.Pieces do
		if not pieces[p.id] and (not p.needs or pieces[p.needs]) then table.insert(out, p) end
	end
	return out
end
-- the dishes these pieces unlock, in book order
function Config.TycoonMenuFor(pieces)
	local out = {}
	for _, m in Config.Tycoon.Menu do
		if pieces[m.unlock] then table.insert(out, m) end
	end
	return out
end
-- shelf cost of one serving's ingredients
function Config.TycoonDishCost(m)
	local c = 0
	for _, gid in m.needs do
		local g = Config.Grocery(gid)
		if g then c += g.price end
	end
	return c
end

return Config
