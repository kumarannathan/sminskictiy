-- SminskiServer (ServerScriptService)
-- Owns everything that matters: coins, XP, unlocks, upgrades, best scores.
-- The client plays the run locally and reports a summary at the end; the
-- server checks it against the server-side run timer before paying out.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("SminskiShared"):WaitForChild("Config"))

local STORE_NAME = "SmiskiRun_PlayerData_v1"
local AUTOSAVE_EVERY = 90

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[SminskiServer] DataStore unavailable, progress will not save:", result)
	end
end

---------------------------------------------------------------------------
-- DATA
---------------------------------------------------------------------------
local function defaultData()
	local owned = {}
	for _, c in Config.Characters do
		if c.default then owned[c.id] = true end
	end
	return {
		Version = 1,
		Coins = 0,
		XP = 0,
		Level = 1,
		BestScore = 0,
		BestDistance = 0,
		-- best single run that was eligible for the all-time distance board:
		-- a ranking character, no Robux-granted revive (see award()). Starts at
		-- 0 for everybody, including existing saves -- reconcile() fills missing
		-- keys from here, and inheriting BestDistance would import exactly the
		-- assisted bests the board exists to keep out.
		BestRankedDistance = 0,
		TotalDistance = 0,
		TotalCoins = 0,
		TotalNearMisses = 0,
		RunsPlayed = 0,
		OwnedCharacters = owned,
		EquippedCharacter = "Glow",
		OwnedOutfits = { None = true },
		EquippedOutfit = "None",
		OwnedSkins = { none = true },
		EquippedSkin = "none",
		Upgrades = {},
		Settings = { Music = true, Sfx = true, Shake = true, AutoCam = true },
		OwnedMaps = { house = true, dollhouse = true },
		SelectedMap = "house",
		Elo = Config.MP.StartElo,
		PeakElo = Config.MP.StartElo,
		RankedPlayed = 0,
		RankedWins = 0,
		MatchesPlayed = 0,
		SurvivalPlayed = 0,
		SurvivalWins = 0,
		BestSurvival = 0,
		MapBest = {}, -- best distance per map (studs)
		-- LIFETIME event counters, written by bump(). City tasks read these;
		-- challenges read their own per-period copies. See Config.Tasks.
		Stats = {},
		TutorialDone = false,
		Login = { streak = 0, lastDay = 0, claimedDay = 0 },
		Garden = { plots = {}, unlocked = 0 }, -- plots[i] = { seed, t0, watered } ; unlocked = extra plots bought
		Receipts = {},   -- PurchaseId -> true. Roblox re-calls ProcessReceipt
		                 -- after a failed save, so a purchase is only granted
		                 -- once this has been written.
		Boost = nil,     -- { mult, until } -- a personal coin boost
		-- Sminski City: owned cars, businesses (id -> last collect os.time),
		-- and the role you picked on arrival (nil = never asked; see the
		-- "role" action). An existing save reaches here with role nil and is
		-- never prompted, because the picker is gated on the tutorial, not on
		-- the role -- they keep the house and the town they already have.
		City = { cars = { convertible = true }, biz = {}, raceBest = 0, role = nil, hood = nil },
		MapStars = {}, -- mastery stars already paid out per map
		Challenges = nil, -- built by refreshChallenges
	}
end

---------------------------------------------------------------------------
-- CHALLENGES: daily + weekly sets, the same for everyone (seeded by the date)
---------------------------------------------------------------------------
local function hashKey(str)
	local h = 7
	for i = 1, #str do h = (h * 31 + str:byte(i)) % 2147483647 end
	return h
end
local function rollSet(kind, key)
	local pool = Config.ChallengePool[kind]
	local rng = Random.new(hashKey(kind .. key))
	local idx = {}
	for i in pool do table.insert(idx, i) end
	local out = {}
	for _ = 1, Config.ChallengeCounts[kind] do
		local pick = table.remove(idx, rng:NextInteger(1, #idx))
		local def = pool[pick]
		local goal = def.goals[rng:NextInteger(1, #def.goals)]
		table.insert(out, { id = def.id, text = def.text:format(goal), goal = goal, stat = def.stat, mode = def.mode, reward = def.reward, progress = 0, claimed = false })
	end
	return out
end
local function refreshChallenges(d)
	local dayKey = os.date("!%Y-%m-%d")
	local weekKey = tostring(math.floor((os.time() + 3 * 86400) / (7 * 86400))) -- weeks, Monday rollover
	local c = d.Challenges
	if type(c) ~= "table" then c = {} d.Challenges = c end
	if c.dayKey ~= dayKey then
		c.dayKey = dayKey
		c.daily = rollSet("daily", dayKey)
	end
	if c.weekKey ~= weekKey then
		c.weekKey = weekKey
		c.weekly = rollSet("weekly", weekKey)
	end
	c.dayEnds = os.time() + (86400 - os.time() % 86400)
	c.weekEnds = (tonumber(weekKey) + 1) * 7 * 86400 - 3 * 86400
	return c
end
-- progress a stat on every live challenge that tracks it
-- ONE CALL SITE FEEDS BOTH SYSTEMS. bump() used to only nudge challenge
-- progress, which is per-day and per-week and gets wiped; city tasks need a
-- LIFETIME counter of the same events. Keeping both here means a task and a
-- challenge can never disagree about how many shifts you have worked, and
-- nothing new has to be remembered at the forty-odd places that call this.
local function bump(d, stat, amount)
	d.Stats = type(d.Stats) == "table" and d.Stats or {}
	d.Stats[stat] = (d.Stats[stat] or 0) + (amount or 0)
	local c = refreshChallenges(d)
	for _, list in { c.daily, c.weekly } do
		for _, ch in list do
			if ch.stat == stat and not ch.claimed then
				if ch.mode == "max" then ch.progress = math.max(ch.progress, amount) else ch.progress += amount end
			end
		end
	end
end

local function reconcile(data)
	local def = defaultData()
	for k, v in def do
		if data[k] == nil then data[k] = v end
	end
	for k, v in def.Settings do
		if data.Settings[k] == nil then data.Settings[k] = v end
	end
	for id in def.OwnedCharacters do
		data.OwnedCharacters[id] = true
	end
	data.OwnedOutfits.None = true
	-- every free map is owned by everyone
	for _, m in Config.Maps do
		if m.free then data.OwnedMaps[m.id] = true end
	end
	refreshChallenges(data)
	if not data.OwnedMaps[data.SelectedMap] then data.SelectedMap = "house" end
	-- drop anything that no longer exists in the config
	if not data.OwnedCharacters[data.EquippedCharacter] then data.EquippedCharacter = "Glow" end
	if not data.OwnedOutfits[data.EquippedOutfit] then data.EquippedOutfit = "None" end
	if type(data.OwnedSkins) ~= "table" then data.OwnedSkins = {} end
	data.OwnedSkins.none = true
	if type(data.EquippedSkin) ~= "string" or not data.OwnedSkins[data.EquippedSkin] then data.EquippedSkin = "none" end
	return data
end

local sessions = {} -- [player] = { data, saveable, run, lastCall = {} }

local function load(player)
	local key = "u_" .. player.UserId
	local data, saveable = nil, false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(key)
			end)
			if ok then
				data = result
				saveable = true
				break
			end
			warn("[SminskiServer] load failed (attempt " .. attempt .. "):", result)
			if tostring(result):find("Studio access") then
				break -- API access is off in this Studio session; no point retrying
			end
			task.wait(1.5 * attempt)
		end
	end
	return reconcile(data or defaultData()), saveable
end

-- THE ONLY THING THAT TOUCHES THE DATASTORE. Everything else goes through
-- save() below, which rate-limits. Call this directly ONLY where a write must
-- happen unconditionally and right now: PlayerRemoving, BindToClose, flushPay.
local function writeNow(player)
	local s = sessions[player]
	-- returns true when there is nothing left to write and false only when a
	-- real write was attempted and failed; flushPay() below depends on that
	-- distinction. Nothing else reads the result.
	if not s or not s.saveable or not store then return true end
	local key = "u_" .. player.UserId
	local snapshot = s.data
	-- EVERY write is a whole-session snapshot, so every write retires the
	-- deferred-pay debt too. Read BEFORE the write and recorded only on a
	-- confirmed success -- see flushPay's comment, which this preserves for
	-- all four write paths rather than just that one.
	local paySeq = s.paySeq or 0
	s.lastWrite = os.clock()
	if s.studioMaps then
		-- Studio test unlocks are never written to the real save
		snapshot = table.clone(s.data)
		snapshot.OwnedMaps = table.clone(s.data.OwnedMaps)
		for id in s.studioMaps do snapshot.OwnedMaps[id] = nil end
		if s.studioMaps[snapshot.SelectedMap] then snapshot.SelectedMap = "house" end
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(key, function()
				return snapshot
			end)
		end)
		if ok then
			s.paySaved = paySeq
			return true
		end
		warn("[SminskiServer] save failed (attempt " .. attempt .. "):", err)
		task.wait(1.5 * attempt)
	end
	return false
end

---------------------------------------------------------------------------
-- RATE-LIMITED SAVE. This is what the ~30 ordinary call sites use.
--
-- WHY. A DataStore key may be written about once every six seconds; past
-- that the request is queued, and a full queue DROPS requests. Every one of
-- those call sites used to `task.spawn(save, player)` the moment anything
-- changed -- a coin spent, a job step, a grocery bought -- so an ordinary
-- minute in the city wrote the same key dozens of times and the live server
-- logged "DataStore request was added to queue" on a single player's key.
--
-- WHAT THIS DOES. Coalesces: the first call schedules a write, every call
-- during the cooldown is absorbed into it, and anything that changed WHILE a
-- write was in flight schedules exactly one more. Because a write is always
-- a whole-session snapshot, one write carries every change made since the
-- last one -- no call site loses anything by being absorbed.
--
-- IT IS FIRE-AND-FORGET. Unlike writeNow it returns nothing, because the
-- write has not happened yet. Nothing reads a return value from these sites.
---------------------------------------------------------------------------
local SAVE_MIN = 7 -- seconds between writes to one key (the engine limit is 6)
local function save(player)
	local s = sessions[player]
	if not s or not s.saveable or not store then return end
	s.saveSeq = (s.saveSeq or 0) + 1
	if s.saveThread then return end -- a write is already queued; it carries this
	s.saveThread = task.spawn(function()
		while true do
			local seq = s.saveSeq
			local since = os.clock() - (s.lastWrite or -math.huge)
			if since < SAVE_MIN then task.wait(SAVE_MIN - since) end
			-- the player may have left while this was waiting; PlayerRemoving
			-- already wrote unconditionally, so there is nothing left to do
			if not sessions[player] then break end
			writeNow(player)
			if s.saveSeq == seq then break end -- nothing new arrived
		end
		s.saveThread = nil
	end)
end

-- COALESCED SAVES, PART ONE. See pay()'s `defer` argument and PAY_FLUSH.
--
-- Only the collect events defer their write, and this is the only thing that
-- may retire the debt. Two rules make it safe, and both were bugs first:
--
--   * the sequence is read BEFORE the write and recorded only on a CONFIRMED
--     success, so a DataStore error leaves the session queued for the next
--     flush instead of quietly dropping the coins it was carrying;
--   * anything paid WHILE the write is in flight bumps paySeq past the value
--     captured here, so it stays queued too. A plain boolean flag cleared
--     after the write would lose that item until something else saved.
--
-- A failed write therefore costs one retry per flush interval, never one per
-- item. Do NOT route PlayerRemoving or BindToClose through this: those must
-- write unconditionally, whatever the counters say.
local function flushPay(player, s)
	local seq = s.paySeq or 0
	if seq == (s.paySaved or 0) then return end
	if writeNow(player) then s.paySaved = seq end
end

---------------------------------------------------------------------------
-- REMOTES
---------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "SminskiRemotes"
remotes.Parent = ReplicatedStorage

local function rf(name)
	local f = Instance.new("RemoteFunction")
	f.Name = name
	f.Parent = remotes
	return f
end

---------------------------------------------------------------------------
-- ALL-TIME LEADERBOARDS (OrderedDataStores; the lobby board reads the JSON)
---------------------------------------------------------------------------
local LB_DEFS = {
	-- _v2, AND THE BUMP IS THE POINT. v1 holds best-single-run metres set with
	-- anything equipped and any revive used. A submission now has to clear two
	-- bars: the equipped Sminski's passive cannot affect distance (the ten
	-- fields in Config.DistancePassives), and no Robux-granted revive was
	-- consumed (the revive pass or the mid-run revive product; an earned
	-- SecondChance revive and a coin-cost revive both still rank). Leaving v1's
	-- entries in place would mean one board holding two different
	-- measurements, with the assisted ones permanently on top, because
	-- lbSubmit only ever raises a score. v2 starts empty. v1 is not deleted,
	-- just unread, so this is one word to revert.
	distance = { store = "SmiskiRun_LB_Distance_v2" }, -- best single run, metres
	wins = { store = "SmiskiRun_LB_ParkWins_v1" }, -- Dog Park Survival wins; Park.lua reads no passives
}
local lbValue = Instance.new("StringValue")
lbValue.Name = "Leaderboards"
lbValue.Value = "{}"
lbValue.Parent = remotes
local lbStores, lbTop, lbNames = {}, { distance = {}, wins = {} }, {}
for id, def in LB_DEFS do
	local ok, st = pcall(function() return DataStoreService:GetOrderedDataStore(def.store) end)
	if ok then lbStores[id] = st end
end
local function lbSubmit(id, userId, value)
	local st = lbStores[id]
	value = math.floor(value or 0)
	if not st or value <= 0 or userId <= 0 then return end
	task.spawn(function()
		pcall(function()
			st:UpdateAsync("u_" .. userId, function(old)
				if old and old >= value then return nil end
				return value
			end)
		end)
	end)
end
local function lbName(userId)
	if lbNames[userId] then return lbNames[userId] end
	local p = Players:GetPlayerByUserId(userId)
	local name = p and p.DisplayName
	if not name then
		local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = ok and n or ("player " .. userId)
	end
	lbNames[userId] = name
	return name
end

---------------------------------------------------------------------------
-- LIVE FEED: what people at this table are up to (lobby side panel)
---------------------------------------------------------------------------
local feedEvent = Instance.new("RemoteEvent")
feedEvent.Name = "Feed"
feedEvent.Parent = remotes
local feedLog = {}
local function feed(text, kind)
	local e = { t = os.time(), text = text, kind = kind or "info" }
	table.insert(feedLog, 1, e)
	if #feedLog > 12 then table.remove(feedLog) end
	feedEvent:FireAllClients(e)
end
rf("GetFeed").OnServerInvoke = function()
	return feedLog
end

-- other clients draw each player's Sminski from these
local function syncLook(player, s)
	player:SetAttribute("Char", s.data.EquippedCharacter)
	player:SetAttribute("Outfit", s.data.EquippedOutfit)
	player:SetAttribute("Skin", s.data.EquippedSkin)
end

-- daily login: bump the streak on the first visit of each (UTC) day
local function refreshLogin(d)
	local today = math.floor(os.time() / 86400)
	local L = d.Login
	if type(L) ~= "table" then L = { streak = 0, lastDay = 0, claimedDay = 0 } d.Login = L end
	if L.lastDay ~= today then
		L.streak = (L.lastDay == today - 1) and (L.streak + 1) or 1
		L.lastDay = today
	end
	return L, today
end

local function publicData(s)
	refreshChallenges(s.data)
	do
		local L, today = refreshLogin(s.data)
		s.data.DailyReady = L.claimedDay ~= today
		s.data.StreakMult = Config.StreakMult(L.streak)
	end
	local d = table.clone(s.data)
	d.Passes = s.passes or {}
	d.Saveable = s.saveable
	d.CapsulesRestricted = s.capsulesRestricted == true
	return d
end

-- tiny per-remote rate limit
local function allow(s, name, gap)
	local now = os.clock()
	local last = s.lastCall[name]
	if last and now - last < (gap or 0.15) then return false end
	s.lastCall[name] = now
	return true
end

local function session(player)
	local s = sessions[player]
	local waited = 0
	while not s and waited < 10 and player.Parent do
		task.wait(0.2)
		waited += 0.2
		s = sessions[player]
	end
	return s
end

rf("GetData").OnServerInvoke = function(player)
	local s = session(player)
	if not s then return nil end
	return publicData(s)
end

rf("StartRun").OnServerInvoke = function(player)
	local s = session(player)
	if not s or not allow(s, "StartRun", 1) then return nil end
	s.run = {
		id = HttpService:GenerateGUID(false),
		start = os.clock(),
		-- SNAPSHOT IT AT THE START, NOT AT THE END. Equip has no mid-run guard
		-- (:604), so reading the equipped character when the run is paid out
		-- would let a player run with Ghost's free shield and swap to Glow
		-- before dying to make the distance rankable.
		ranked = Config.RanksForDistance(s.data.EquippedCharacter),
		paidRevives = 0,
		freeRevives = (s.data.Upgrades.SecondChance or 0) + (s.passes and s.passes.revive and (Config.Pass("revive").freeRevive or 0) or 0),
		-- THE SAME TOTAL, SPLIT BY WHERE IT CAME FROM, for the distance board.
		-- `freeRevives` above stays the one live counter the Revive remote
		-- decrements and the client sees as `freeLeft` -- nothing about revives
		-- changes. These two only record how that total was composed:
		--   freeEarned  the SecondChance upgrade, bought with earned coins
		--   freeRobux   the revive PASS, and the mid-run revive PRODUCT, which
		--               adds to both this and freeRevives in ProcessReceipt
		-- Free revives are interchangeable in play, so they are accounted
		-- EARNED FIRST -- the reading most favourable to the player. That makes
		-- "a Robux revive was necessarily consumed" exact rather than fuzzy:
		--   consumed        = freeEarned + freeRobux - freeRevives
		--   robux consumed <=> consumed > freeEarned <=> freeRevives < freeRobux
		freeEarned = (s.data.Upgrades.SecondChance or 0),
		freeRobux = (s.passes and s.passes.revive and (Config.Pass("revive").freeRevive or 0) or 0),
	}
	s.data.RunsPlayed += 1
	local mapDef = Config.Map(s.data.SelectedMap or "house")
	player:SetAttribute("RunMap", mapDef.name)
	feed(player.DisplayName .. " is running " .. mapDef.name, "run")
	return s.run.id
end

rf("Revive").OnServerInvoke = function(player, runId, useFree)
	local s = session(player)
	if not s or not s.run or s.run.id ~= runId or not allow(s, "Revive", 0.5) then
		return { ok = false }
	end
	if useFree then
		if s.run.freeRevives > 0 then
			s.run.freeRevives -= 1
			return { ok = true, coins = s.data.Coins, freeLeft = s.run.freeRevives }
		end
		return { ok = false }
	end
	local cost = Config.ReviveBaseCost * (2 ^ s.run.paidRevives)
	if s.data.Coins < cost then
		return { ok = false, reason = "coins" }
	end
	s.data.Coins -= cost
	s.run.paidRevives += 1
	return { ok = true, coins = s.data.Coins, freeLeft = s.run.freeRevives }
end

-- pays out a finished run (solo or multiplayer) after sanity-capping the
-- client's numbers against the server-side elapsed time
local function passCoinMult(s)
	local k = Config.StreakMult(s.data.Login and s.data.Login.streak or 1)
	for _, p in Config.Passes do
		if p.coinMult and s.passes and s.passes[p.id] then k *= p.coinMult end
	end
	return k
end

local function award(player, s, stats, elapsed, ranked)
	local function num(v)
		v = tonumber(v) or 0
		if v ~= v or v == math.huge or v < 0 then return 0 end
		return v
	end
	local maxDistance = elapsed * Config.MaxSpeed * 1.4 + 100
	local distance = math.min(num(stats.distance), maxDistance)
	local maxCoins = distance * 0.35 * 2 + 50 -- dense trails, 2x powerup
	local coins = math.floor(math.min(num(stats.coins), maxCoins))
	local nearMisses = math.floor(math.min(num(stats.nearMisses), distance / 8 + 5))
	local maxScore = (distance * 0.5 + coins * 10 + nearMisses * 25 + distance) * 8
	local score = math.floor(math.min(num(stats.score), maxScore))
	local bestCombo = math.floor(math.clamp(num(stats.bestCombo), 1, #Config.ComboSteps))

	local d = s.data
	local xp = Config.XPForRun(distance, coins, nearMisses)
	local baseCoins = coins
	coins = math.floor(coins * passCoinMult(s)) -- VIP / 2x Coins passes
	local oldLevel = d.Level
	d.Coins += coins
	d.TotalCoins += coins
	d.TotalDistance += distance
	d.TotalNearMisses += nearMisses
	d.XP += xp
	d.Level = Config.LevelFromXP(d.XP)
	local newBest = score > d.BestScore
	if newBest then d.BestScore = score end
	-- the personal best always counts, whatever was equipped and however the
	-- run was revived. It is the player's own number, in their own UI.
	if distance > d.BestDistance then
		d.BestDistance = distance
	end
	-- THE BOARD KEEPS ITS OWN BEST, AND THE COMPARISON HAS TO BE SEPARATE.
	--
	-- Nesting this inside the personal-best test above looks equivalent and is
	-- not: a player whose overall best was set with a non-ranking Sminski could
	-- then never submit anything until they beat that assisted number with a
	-- ranking one. Since every existing save carries such a best, the v2 board
	-- would have stayed near-empty for precisely the players who play most --
	-- the same silent-emptying failure as excluding every passive.
	--
	-- Two independent bests, two independent comparisons. This one only moves
	-- on runs the board will actually accept.
	if ranked and distance > (d.BestRankedDistance or 0) then
		d.BestRankedDistance = distance
		lbSubmit("distance", player.UserId, distance / Config.StudsPerMeter)
	end
	-- map mastery: stars from the best distance on this map, coins per new star
	local mapId = type(stats.map) == "string" and Config.Map(stats.map).id == stats.map and stats.map or "house"
	d.MapBest[mapId] = math.max(d.MapBest[mapId] or 0, distance)
	local stars = Config.MasteryStars(d.MapBest[mapId])
	local paid = d.MapStars[mapId] or 0
	local masteryCoins = 0
	for i = paid + 1, stars do masteryCoins += Config.Mastery.rewards[i] or 0 end
	if stars > paid then
		d.MapStars[mapId] = stars
		d.Coins += masteryCoins
		d.TotalCoins += masteryCoins
	end
	-- challenges
	bump(d, "coins", coins)
	bump(d, "runM", distance / Config.StudsPerMeter)
	bump(d, "totalM", distance / Config.StudsPerMeter)
	bump(d, "near", nearMisses)
	bump(d, "runs", 1)
	bump(d, "combo", bestCombo)

	do
		local m = math.floor(distance / Config.StudsPerMeter)
		if m >= 60 then
			feed(("%s ran %sm in %s%s"):format(player.DisplayName, tostring(m), Config.Map(mapId).name, newBest and "  ·  NEW BEST!" or ""), newBest and "best" or "result")
		end
		if d.Level > oldLevel then feed(player.DisplayName .. " reached level " .. d.Level, "level") end
	end
	task.spawn(save, player)
	return {
		coinsEarned = coins,
		passBonus = coins - baseCoins,
		xpEarned = xp,
		score = score,
		distance = distance,
		nearMisses = nearMisses,
		newBest = newBest,
		levelUp = d.Level > oldLevel,
		bestCombo = bestCombo,
		newStars = stars > paid and stars or nil,
		masteryCoins = masteryCoins,
		map = mapId,
		-- whether this run could go to the all-time distance board, so a client
		-- can say so rather than leaving a player wondering why their best run
		-- never appears. Nothing reads it yet; it costs one boolean.
		ranked = ranked == true,
		data = publicData(s),
	}
end

rf("EndRun").OnServerInvoke = function(player, runId, stats)
	local s = session(player)
	if not s or not s.run or s.run.id ~= runId or type(stats) ~= "table" then
		return nil
	end
	local run = s.run
	s.run = nil
	-- Rankable for the all-time distance board? Two server-side facts, each
	-- captured at the point it was true rather than read back now:
	--   run.ranked   the character equipped when the run STARTED (see StartRun;
	--                Equip has no mid-run guard, so reading it here is gamed)
	--   freeRevives < freeRobux   a Robux-granted revive was necessarily used,
	--                whether from the pass or the mid-run product. Coin-cost
	--                revives (run.paidRevives) and the earned SecondChance
	--                allowance both still rank -- the board excludes Robux
	--                assistance, not effort.
	local robuxRevived = (run.freeRevives or 0) < (run.freeRobux or 0)
	return award(player, s, stats, os.clock() - run.start, run.ranked and not robuxRevived)
end

rf("BuyUpgrade").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "BuyUpgrade") then return { ok = false } end
	local u = Config.Upgrade(id)
	if not u then return { ok = false } end
	local lvl = s.data.Upgrades[id] or 0
	local cost = u.costs[lvl + 1]
	if not cost then return { ok = false, reason = "max" } end
	if s.data.Coins < cost then return { ok = false, reason = "coins" } end
	s.data.Coins -= cost
	s.data.Upgrades[id] = lvl + 1
	return { ok = true, data = publicData(s) }
end

-- Roblox policy: in some countries paid random items are restricted. Capsules
-- only cost earned coins today (coins can't be bought with Robux), so they're
-- not "paid"; if Config.CapsulesArePaid is ever turned on, restricted players
-- can't open them.
local PolicyService = game:GetService("PolicyService")
local policyCache = {}
local function paidRandomRestricted(player)
	if policyCache[player] == nil then
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		-- if the lookup fails, play it safe and treat the player as restricted
		policyCache[player] = not ok or (info and info.ArePaidRandomItemsRestricted == true) or false
	end
	return policyCache[player]
end
Players.PlayerRemoving:Connect(function(player) policyCache[player] = nil end)

local rollCapsule
rf("OpenCapsule").OnServerInvoke = function(player)
	local s = session(player)
	if not s or not allow(s, "OpenCapsule", 0.8) then return { ok = false } end
	if Config.CapsulesArePaid and paidRandomRestricted(player) then
		return { ok = false, reason = "restricted" }
	end
	if s.data.Coins < Config.CapsuleCost then return { ok = false, reason = "coins" } end
	s.data.Coins -= Config.CapsuleCost
	return rollCapsule(player, s)
end

-- roll rarity, then a character of that rarity (paid from coins, or a free gift)
rollCapsule = function(player, s)
	local total = 0
	for _, r in Config.Rarities do total += r.weight end
	local roll = math.random() * total
	local rarity = Config.Rarities[1]
	for _, r in Config.Rarities do
		roll -= r.weight
		if roll <= 0 then
			rarity = r
			break
		end
	end
	local pool = {}
	for _, c in Config.Characters do
		if c.rarity == rarity.id then table.insert(pool, c) end
	end
	local char = pool[math.random(1, #pool)]
	local dup = s.data.OwnedCharacters[char.id] == true
	local refund = 0
	if dup then
		refund = rarity.refund
		s.data.Coins += refund
	else
		s.data.OwnedCharacters[char.id] = true
	end
	task.spawn(save, player)
	bump(s.data, "capsules", 1)
	if rarity.id ~= "Common" and not dup then feed(player.DisplayName .. " found " .. char.name .. " (" .. rarity.id .. ")!", "rare") end
	return { ok = true, character = char.id, rarity = rarity.id, duplicate = dup, refund = refund, data = publicData(s) }
end

rf("ClaimDaily").OnServerInvoke = function(player)
	local s = session(player)
	if not s or not allow(s, "ClaimDaily", 0.5) then return { ok = false } end
	local d = s.data
	local L, today = refreshLogin(d)
	if L.claimedDay == today then return { ok = false, reason = "already claimed today" } end
	L.claimedDay = today
	local day = (L.streak - 1) % #Config.Daily + 1
	local gift = Config.Daily[day]
	local out = { ok = true, day = day, streak = L.streak, coins = 0 }
	if gift.outfit then
		if d.OwnedOutfits[gift.outfit] then
			out.coins += gift.fallbackCoins or 0
		else
			d.OwnedOutfits[gift.outfit] = true
			out.outfit = gift.outfit
			out.coins += gift.coins or 0
		end
	elseif gift.coins then
		out.coins += gift.coins
	end
	d.Coins += out.coins
	d.TotalCoins += out.coins
	if gift.capsule then
		out.capsule = rollCapsule(player, s)
	end
	if L.streak >= 7 and day == 7 then feed(player.DisplayName .. " hit a " .. L.streak .. "-day streak!", "best") end
	task.spawn(save, player)
	out.data = publicData(s)
	return out
end

rf("Equip").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "Equip") then return { ok = false } end
	if type(id) ~= "string" or not s.data.OwnedCharacters[id] then return { ok = false } end
	s.data.EquippedCharacter = id
	syncLook(player, s)
	return { ok = true, data = publicData(s) }
end

rf("BuyOutfit").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "BuyOutfit") then return { ok = false } end
	local o = type(id) == "string" and Config.Outfit(id)
	if not o or o.id ~= id then return { ok = false } end
	if s.data.OwnedOutfits[id] then return { ok = false, reason = "owned" } end
	if o.exclusive then return { ok = false, reason = "gift" } end
	if o.level and s.data.Level < o.level then return { ok = false, reason = "level", level = o.level } end
	if s.data.Coins < o.price then return { ok = false, reason = "coins" } end
	s.data.Coins -= o.price
	s.data.OwnedOutfits[id] = true
	s.data.EquippedOutfit = id
	-- the "spend some of it" city task (Config.Tasks). Cosmetics are the
	-- cheapest thing a new player can buy, so this is the purchase the
	-- opening sequence is actually waiting for.
	bump(s.data, "cityBuys", 1)
	task.spawn(save, player)
	syncLook(player, s)
	return { ok = true, data = publicData(s) }
end

rf("EquipOutfit").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "EquipOutfit") then return { ok = false } end
	if type(id) ~= "string" or not s.data.OwnedOutfits[id] then return { ok = false } end
	s.data.EquippedOutfit = id
	syncLook(player, s)
	return { ok = true, data = publicData(s) }
end

rf("BuySkin").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "BuySkin") then return { ok = false } end
	local k = type(id) == "string" and Config.Skin(id)
	if not k or k.id ~= id or id == "none" then return { ok = false } end
	if s.data.OwnedSkins[id] then return { ok = false, reason = "owned" } end
	if k.exclusive then return { ok = false, reason = "gift" } end
	if k.level and s.data.Level < k.level then return { ok = false, reason = "level", level = k.level } end
	if s.data.Coins < k.price then return { ok = false, reason = "coins" } end
	s.data.Coins -= k.price
	s.data.OwnedSkins[id] = true
	s.data.EquippedSkin = id
	bump(s.data, "cityBuys", 1)
	task.spawn(save, player)
	syncLook(player, s)
	feed(player.DisplayName .. " put on the " .. k.name .. " skin!", "rare")
	return { ok = true, data = publicData(s) }
end

rf("EquipSkin").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "EquipSkin") then return { ok = false } end
	if type(id) ~= "string" or not s.data.OwnedSkins[id] then return { ok = false } end
	s.data.EquippedSkin = id
	syncLook(player, s)
	return { ok = true, data = publicData(s) }
end

rf("BuyMap").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "BuyMap") then return { ok = false } end
	local m = type(id) == "string" and Config.Map(id)
	if not m or m.id ~= id or m.free then return { ok = false } end
	if s.data.OwnedMaps[id] then return { ok = false, reason = "owned" } end
	if not m.price or s.data.Coins < m.price then return { ok = false, reason = "coins" } end
	s.data.Coins -= m.price
	s.data.OwnedMaps[id] = true
	s.data.SelectedMap = id
	task.spawn(save, player)
	return { ok = true, data = publicData(s) }
end

rf("SelectMap").OnServerInvoke = function(player, id)
	local s = session(player)
	if not s or not allow(s, "SelectMap") then return { ok = false } end
	if type(id) ~= "string" or not s.data.OwnedMaps[id] then return { ok = false, reason = "locked" } end
	s.data.SelectedMap = id
	return { ok = true, data = publicData(s) }
end

-- Robux game passes for maps (optional)
local mapPassEvent = Instance.new("RemoteEvent")
mapPassEvent.Name = "DataChanged"
mapPassEvent.Parent = remotes

-- AUTO-COLLECT paid out while you were doing something else: (coins, shops)
local autoEvent = Instance.new("RemoteEvent")
autoEvent.Name = "AutoCollected"
autoEvent.Parent = remotes

-- a world job (taxi/parcels/litter/fields) credited a task to your shift
local jobEvent = Instance.new("RemoteEvent")
jobEvent.Name = "JobCredited"
jobEvent.Parent = remotes

-- which game passes this player owns, and the perks that come with them
local function refreshPasses(player)
	local s = sessions[player]
	if not s then return end
	s.passes = s.passes or {}
	local changed = false
	for _, p in Config.Passes do
		local owns = false
		if RunService:IsStudio() and Config.StudioOwnPasses then
			owns = true
		elseif p.gamePassId then
			local ok, res = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, p.gamePassId)
			owns = ok and res == true
		end
		if owns and not s.passes[p.id] then
			s.passes[p.id] = true
			changed = true
		end
	end
	if s.passes.vip then
		player:SetAttribute("VIP", true)
		local outfit = Config.Pass("vip").outfit
		if outfit and not s.data.OwnedOutfits[outfit] then s.data.OwnedOutfits[outfit] = true changed = true end
	end
	if s.passes.greenthumb then
		local d = s.data
		if type(d.Garden) ~= "table" then d.Garden = { plots = {}, unlocked = 0 } end
		local all = Config.Garden.MaxPlots - Config.Garden.StartPlots
		if (d.Garden.unlocked or 0) < all then d.Garden.unlocked = all changed = true end
	end
	if s.passes.maps then
		for _, m in Config.Maps do
			if not s.data.OwnedMaps[m.id] then s.data.OwnedMaps[m.id] = true changed = true end
		end
	end
	-- THE STARTER PACK pays out exactly once. Without the flag, re-checking
	-- pass ownership on every join would hand out the coins again each time.
	if s.passes.starter and not s.data.StarterClaimed then
		local pk = Config.Pass("starter")
		s.data.StarterClaimed = true
		s.data.Coins += pk.starterCoins
		s.data.TotalCoins += pk.starterCoins
		if type(s.data.City) == "table" then s.data.City.cars[pk.starterCar] = true end
		if type(s.data.Garden) == "table" then
			s.data.Garden.unlocked = math.max(s.data.Garden.unlocked or 0, pk.starterPlots)
		end
		changed = true
		feed(player.DisplayName .. " picked up the Starter Pack", "info")
	end
	-- perks the client needs to know about are published as attributes
	player:SetAttribute("WalkMult", s.passes.speed and Config.Pass("speed").walkMult or nil)
	player:SetAttribute("CarMult", s.passes.speed and Config.Pass("speed").carMult or nil)
	player:SetAttribute("AutoCollect", s.passes.auto or nil)
	if changed then
		mapPassEvent:FireClient(player, publicData(s))
	end
end

local function grantMapPasses(player)
	local s = sessions[player]
	if not s then return end
	local changed = false
	for _, m in Config.Maps do
		if m.gamePassId and not s.data.OwnedMaps[m.id] then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, m.gamePassId)
			if ok and owns then
				s.data.OwnedMaps[m.id] = true
				changed = true
			end
		end
	end
	if changed then
		mapPassEvent:FireClient(player, publicData(s))
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased then
		grantMapPasses(player)
		refreshPasses(player)
	end
end)

rf("ClaimChallenge").OnServerInvoke = function(player, kind, index)
	local s = session(player)
	if not s or not allow(s, "ClaimChallenge", 0.3) then return { ok = false } end
	local c = refreshChallenges(s.data)
	local list = kind == "daily" and c.daily or kind == "weekly" and c.weekly or nil
	local ch = list and type(index) == "number" and list[index]
	if not ch or ch.claimed or ch.progress < ch.goal then return { ok = false } end
	ch.claimed = true
	s.data.Coins += ch.reward
	s.data.TotalCoins += ch.reward
	task.spawn(save, player)
	return { ok = true, data = publicData(s), reward = ch.reward }
end

rf("TutorialDone").OnServerInvoke = function(player)
	local s = session(player)
	if not s then return false end
	s.data.TutorialDone = true
	task.spawn(save, player)
	return true
end

---------------------------------------------------------------------------
-- GARDEN
---------------------------------------------------------------------------
local function gardenOf(d)
	if type(d.Garden) ~= "table" then d.Garden = {} end
	d.Garden.plots = d.Garden.plots or {}
	d.Garden.unlocked = d.Garden.unlocked or 0
	return d.Garden
end
local function plotCount(g)
	return math.min(Config.Garden.MaxPlots, Config.Garden.StartPlots + (g.unlocked or 0))
end
local function plotLeft(p)
	local def = Config.Seed(p.seed)
	if not def then return 0 end
	local total = def.grow * (p.watered and (1 - Config.Garden.WaterCut) or 1)
	return math.max(0, p.t0 + total - os.time())
end
rf("Garden").OnServerInvoke = function(player, action, a1, a2)
	local s = session(player)
	if not s or not allow(s, "Garden", 0.2) then return { ok = false } end
	local d = s.data
	local g = gardenOf(d)
	local i = tonumber(a1)
	if action == "plant" then
		local def = type(a2) == "string" and Config.Seed(a2)
		if not def or not i or i < 1 or i > plotCount(g) or g.plots[tostring(i)] then return { ok = false } end
		if d.Level < (def.level or 1) then return { ok = false, reason = "level", level = def.level } end
		if d.Coins < def.cost then return { ok = false, reason = "coins" } end
		d.Coins -= def.cost
		g.plots[tostring(i)] = { seed = def.id, t0 = os.time(), watered = false }
	elseif action == "water" then
		local p = i and g.plots[tostring(i)]
		if not p or p.watered or plotLeft(p) <= 0 then return { ok = false } end
		p.watered = true
	elseif action == "harvest" or action == "harvestAll" then
		-- one plot, or every ripe plot at once
		local list = {}
		if action == "harvestAll" then
			for k = 1, plotCount(g) do table.insert(list, k) end
		else
			list = { i }
		end
		local coins, xp, n, lastName = 0, 0, 0, nil
		local oldLevel = d.Level
		for _, k in list do
			local p = k and g.plots[tostring(k)]
			if p and plotLeft(p) <= 0 then
				local def = Config.Seed(p.seed)
				g.plots[tostring(k)] = nil
				if def then
					local c = math.floor(def.sell * passCoinMult(s))
					coins += c
					xp += def.xp
					n += 1
					lastName = def.name
					if def.sell >= 700 then feed(player.DisplayName .. " harvested a " .. def.name .. "!", "rare") end
				end
			end
		end
		if n == 0 then return { ok = false } end
		d.Coins += coins
		d.TotalCoins += coins
		d.XP += xp
		d.Level = Config.LevelFromXP(d.XP)
		d.Harvests = (d.Harvests or 0) + n
		bump(d, "harvest", n)
		bump(d, "coins", coins)
		if d.Level > oldLevel then feed(player.DisplayName .. " reached level " .. d.Level, "level") end
		task.spawn(save, player)
		return { ok = true, data = publicData(s), coins = coins, xp = xp, count = n, name = n == 1 and lastName or (n .. " plants") }
	elseif action == "unlock" then
		local n = g.unlocked or 0
		local cost = Config.Garden.PlotCosts[n + 1]
		if not cost or plotCount(g) >= Config.Garden.MaxPlots then return { ok = false } end
		if d.Coins < cost then return { ok = false, reason = "coins" } end
		d.Coins -= cost
		g.unlocked = n + 1
	else
		return { ok = false }
	end
	task.spawn(save, player)
	return { ok = true, data = publicData(s) }
end

rf("SetSetting").OnServerInvoke = function(player, key, value)
	local s = session(player)
	if not s or not allow(s, "SetSetting", 0.1) then return false end
	if s.data.Settings[key] == nil or type(value) ~= "boolean" then return false end
	s.data.Settings[key] = value
	return true
end

-- Optional Robux revive. Create a Developer Product (Creator Dashboard ->
-- your experience -> Monetization -> Developer Products) and put its id in
-- Config.ReviveProductId. The client then offers a Robux revive button.
local reviveEvent = Instance.new("RemoteEvent")
reviveEvent.Name = "RobuxRevived"
reviveEvent.Parent = remotes

-- SERVER-WIDE BOOST: one at a time, the longest-running wins. Everyone on
-- the server shares it and everyone is told who paid for it.
local serverBoost = nil -- { mult, until, who }
local boostEvent = Instance.new("RemoteEvent")
boostEvent.Name = "Boost"
boostEvent.Parent = ReplicatedStorage
local function boostState()
	local now = os.time()
	if serverBoost and serverBoost.untilT <= now then serverBoost = nil end
	return serverBoost
end
local function announceBoost()
	local b = boostState()
	boostEvent:FireAllClients(b and { mult = b.mult, untilT = b.untilT, who = b.who } or nil)
end
-- the multiplier a player currently gets from boosts (personal x server)
local function boostMult(player, s)
	local m = 1
	local now = os.time()
	if s and s.data.Boost and s.data.Boost.untilT > now then m *= s.data.Boost.mult end
	local b = boostState()
	if b then m *= b.mult end
	return m
end

-- Restaurant Row's products are granted by the tycoon block, far below (it
-- owns the stock and the till). Forward-declared the way assignHouse is.
local tycoonProduct
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local s = sessions[player]
	if not s then return Enum.ProductPurchaseDecision.NotProcessedYet end

	-- ALREADY PAID? Roblox calls this again whenever the previous call did not
	-- report success, so without this ledger one purchase can pay out twice.
	if type(s.data.Receipts) ~= "table" then s.data.Receipts = {} end
	local key = tostring(receipt.PurchaseId)
	if s.data.Receipts[key] then return Enum.ProductPurchaseDecision.PurchaseGranted end

	if Config.ReviveProductId and receipt.ProductId == Config.ReviveProductId then
		-- a revive bought with Robux, mid-run. It goes into the live counter as
		-- before AND into the Robux side of the split, so the distance board
		-- can tell it apart from a second chance the player earned.
		if s.run then
			s.run.freeRevives += 1
			s.run.freeRobux = (s.run.freeRobux or 0) + 1
		end
		reviveEvent:FireClient(player)
		s.data.Receipts[key] = true
		task.spawn(save, player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local prod = Config.ProductByAssetId(receipt.ProductId)
	if not prod then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local granted = false
	if prod.kind == "coins" then
		s.data.Coins += prod.coins
		s.data.TotalCoins += prod.coins
		granted = true
		feed(player.DisplayName .. " topped up " .. prod.coins .. " coins", "info")
	elseif prod.kind == "boost" then
		local untilT = os.time() + prod.minutes * 60
		if prod.scope == "server" then
			local cur = boostState()
			if not cur or untilT > cur.untilT then
				serverBoost = { mult = prod.mult, untilT = untilT, who = player.DisplayName }
			end
			announceBoost()
			feed(player.DisplayName .. " started " .. prod.mult .. "x COINS for the whole server!", "rare")
		else
			local cur = s.data.Boost
			s.data.Boost = (cur and cur.untilT > untilT) and cur or { mult = prod.mult, untilT = untilT }
		end
		granted = true
	elseif prod.kind == "skipBiz" then
		-- push every owned business back to its cap so it is ready to collect
		local c = s.data.City
		local back = os.time() - Config.City.CapMinutes * 60
		for id in c.biz or {} do c.biz[id] = back end
		-- the restaurant too: a finished shift, as far as its stock will go
		if type(c.tycoon) == "table" and tonumber(c.tycoon.since) then c.tycoon.since = back end
		granted = true
	elseif prod.kind == "tycoonRush" or prod.kind == "tycoonPantry" or prod.kind == "tycoonChain" then
		granted = tycoonProduct ~= nil and tycoonProduct(player, s, prod) == true
	elseif prod.kind == "skipFarm" then
		local g = s.data.Garden
		local ripe = Config.City.RipeSeconds or 600
		local back = os.time() - ripe
		for _, plot in g.plots or {} do
			if type(plot) == "table" and plot.t0 then plot.t0 = back end
		end
		local st = s.city
		if st then for i in st.plots or {} do st.plots[i] = os.clock() - ripe end end
		granted = true
	end

	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
	s.data.Receipts[key] = true
	task.spawn(save, player)
	mapPassEvent:FireClient(player, publicData(s))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------------
-- CHARACTERS: every player gets a tiny invisible Humanoid body; each client
-- draws the player's Sminski on top of it. It walks the neighborhood hub and
-- the Dog Park Survival arena (the runner itself is still fully client-side).
---------------------------------------------------------------------------
local Places = require(ReplicatedStorage.SminskiShared:WaitForChild("Places"))
Players.CharacterAutoLoads = false

do
	local sp = game:GetService("StarterPlayer")
	local old = sp:FindFirstChild("StarterCharacter")
	if old then old:Destroy() end
	local m = Instance.new("Model")
	m.Name = "StarterCharacter"
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(1.6, 2, 1.6)
	hrp.Transparency = 1
	hrp.CanCollide = true
	hrp.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Transparency = 1
	head.CanCollide = false
	head.Massless = true
	head.CFrame = hrp.CFrame * CFrame.new(0, 1.4, 0)
	head.Parent = m
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = head
	weld.Parent = hrp
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 1.9
	hum.WalkSpeed = Config.Park.WalkSpeed
	hum.UseJumpPower = false
	hum.JumpHeight = Config.Park.JumpHeight
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = m
	m.PrimaryPart = hrp
	m.Parent = sp
end

-- invisible ground under the hub and the park (both are drawn on each client)
do
	local ground = Instance.new("Model")
	ground.Name = "SminskiGround"
	ground.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	-- a floor + four invisible walls (hx/hz = half extents; margin keeps the walls
	-- just inside the table edge so nobody walks off the side table)
	local function slab(centre, hx, hz, name, margin)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Transparency = 1
		p.Size = Vector3.new(hx * 2 + margin * 2, 4, hz * 2 + margin * 2)
		p.CFrame = CFrame.new(centre - Vector3.new(0, 2, 0))
		p.Parent = ground
		for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			local w = Instance.new("Part")
			w.Name = name .. "Wall"
			w.Anchored = true
			w.Transparency = 1
			w.Size = side.X ~= 0 and Vector3.new(4, 120, hz * 2 + 60) or Vector3.new(hx * 2 + 60, 120, 4)
			local off = side.X ~= 0 and (hx + margin) or (hz + margin)
			w.CFrame = CFrame.new(centre + side * (off + 2) + Vector3.new(0, 60, 0))
			w.Parent = ground
		end
	end
	slab(Places.HUB, Places.TABLE_X, Places.TABLE_Z, "HubGround", -3)
	slab(Places.ARENA, Places.ARENA_HALF, Places.ARENA_HALF, "ParkGround", 20)
	slab(Places.CITY, Places.CITY_HALF, Places.CITY_HALF, "CityGround", 6)
	-- the harbour: open the city's north wall at Main St, fence in the boardwalk
	do
		local C = Places.CITY
		for _, w in ground:GetChildren() do
			if w.Name == "CityGroundWall" and w.Position.Z > C.Z + 900 and w.Size.X > 500 then
				for _, seg in { { -1040, -60 }, { 60, 1040 } } do
					local p = w:Clone()
					p.Size = Vector3.new(seg[2] - seg[1], w.Size.Y, w.Size.Z)
					p.CFrame = CFrame.new(C.X + (seg[1] + seg[2]) / 2, w.Position.Y, w.Position.Z)
					p.Parent = ground
				end
				for _, e in { { Vector3.new(4, 120, 220), Vector3.new(-470, 60, 1110) }, { Vector3.new(4, 120, 220), Vector3.new(470, 60, 1110) }, { Vector3.new(944, 120, 4), Vector3.new(0, 60, 1220) } } do
					local p = w:Clone()
					p.Name = "HarbourWall"
					p.Size = e[1]
					p.CFrame = CFrame.new(C + e[2])
					p.Parent = ground
				end
				w:Destroy()
			end
		end
	end
	-- the gate: open the table's back wall where the bridge leaves, and give
	-- the bridge + tunnel a floor and side walls into the bedroom wall
	do
		local gx = Places.HUB.X + Places.HubGateX
		for _, w in ground:GetChildren() do
			if w.Name == "HubGroundWall" and w.Position.Z < Places.HUB.Z - 20 and w.Size.X > 50 then
				local z = w.Position.Z
				local x0, x1 = w.Position.X - w.Size.X / 2, w.Position.X + w.Size.X / 2
				local gap0, gap1 = gx - 13, gx + 13
				for _, seg in { { x0, gap0 }, { gap1, x1 } } do
					local p = w:Clone()
					p.Size = Vector3.new(seg[2] - seg[1], w.Size.Y, w.Size.Z)
					p.CFrame = CFrame.new((seg[1] + seg[2]) / 2, w.Position.Y, z)
					p.Parent = ground
				end
				w:Destroy()
			end
		end
		local z0, z1 = Places.HUB.Z - Places.TABLE_Z + 6, Places.HUB.Z + Places.HubGateZ - 30
		local floor = Instance.new("Part")
		floor.Name = "GateFloor"
		floor.Anchored = true
		floor.Transparency = 1
		floor.Size = Vector3.new(26, 4, z0 - z1)
		floor.CFrame = CFrame.new(gx, Places.HUB.Y - 2, (z0 + z1) / 2)
		floor.Parent = ground
		for _, sx in { -1, 1 } do
			local wall = floor:Clone()
			wall.Name = "GateWall"
			wall.Size = Vector3.new(2, 40, z0 - z1)
			wall.CFrame = CFrame.new(gx + sx * 14, Places.HUB.Y + 20, (z0 + z1) / 2)
			wall.Parent = ground
		end
		local cap = floor:Clone()
		cap.Name = "GateEnd"
		cap.Size = Vector3.new(30, 40, 2)
		cap.CFrame = CFrame.new(gx, Places.HUB.Y + 20, z1 - 1)
		cap.Parent = ground
	end
	ground.Parent = workspace
end

local hubSpawnCF = CFrame.new(Places.HUB + Places.HubSpawn + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, math.pi, 0)

local assignHouse -- defined further down (houses need Places.cityLots)
-- everyone starts out in Sminski City: newcomers at the City Gate (the
-- tutorial walks them home), regulars on their own doorstep
local function citySpawnCF(player, s)
	local house = assignHouse(player, s)
	local lot = house and Places.cityLots()[house]
	local toured = s and type(s.data.City) == "table" and s.data.City.tutorial
	if lot and toured then
		local dir = Vector3.new(math.sin(lot.face), 0, math.cos(lot.face))
		local p = Places.CITY + lot.door - dir * 4 + Vector3.new(0, 3.2, 0)
		return CFrame.lookAt(p, p - dir)
	end
	return CFrame.new(Places.CITY + Places.CitySpawn + Vector3.new(math.random(-8, 8), 3.2, math.random(-4, 4))) * CFrame.Angles(0, math.pi, 0)
end

local function placeCharacter(player, cf, activity)
	if activity then player:SetAttribute("Activity", activity) end
	local c = player.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		player:LoadCharacter()
		c = player.Character
		hrp = c and c:FindFirstChild("HumanoidRootPart")
	end
	if c and hrp then
		hrp.Anchored = false
		hrp.AssemblyLinearVelocity = Vector3.zero
		c:PivotTo(cf)
	end
end

local function freeze(player, on)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = on and 0 or Config.Park.WalkSpeed
		hum.JumpHeight = on and 0 or Config.Park.JumpHeight
	end
end

-- every player gets a house in Sminski City (kept between visits when free)
local cityHouseOf = {} -- [lotIndex] = player
function assignHouse(player, s)
	local cur = player:GetAttribute("CityHouse")
	if cur and cityHouseOf[cur] == player then return cur end
	local lots = Places.cityLots()
	local want = s and type(s.data.City) == "table" and tonumber(s.data.City.house)
	local pick
	if want and lots[want] and lots[want].kind == "house" and not cityHouseOf[want] then
		pick = want
	else
		local free = {}
		for i, l in lots do
			if l.kind == "house" and not cityHouseOf[i] then table.insert(free, i) end
		end
		if #free == 0 then return nil end
		pick = free[math.random(1, #free)]
	end
	cityHouseOf[pick] = player
	player:SetAttribute("CityHouse", pick)
	if s then
		if type(s.data.City) ~= "table" then s.data.City = {} end
		s.data.City.house = pick
	end
	return pick
end
Players.PlayerRemoving:Connect(function(player)
	for i, p in cityHouseOf do
		if p == player then cityHouseOf[i] = nil end
	end
end)

local activityEvent = Instance.new("RemoteEvent")
activityEvent.Name = "SetActivity"
activityEvent.Parent = remotes
-- the client says when it goes into / comes out of a runner (solo or squad) run
activityEvent.OnServerEvent:Connect(function(player, activity, where)
	if activity ~= "run" and activity ~= "hub" and activity ~= "city" then return end
	if player:GetAttribute("Activity") == "park" then return end
	local was = player:GetAttribute("Activity")
	player:SetAttribute("Activity", activity)
	-- walking out of the city writes whatever a deferred pay() left unwritten
	-- (a collect sweep), so the coins are on disk before the player is
	-- elsewhere. flushPay no-ops if the flush loop already got there.
	if was == "city" and activity ~= "city" then
		local s = sessions[player]
		if s then task.spawn(flushPay, player, s) end
	end
	if activity == "city" then
		player:SetAttribute("Driving", nil)
		player:SetAttribute("CityPose", nil)
		local s = sessions[player]
		placeCharacter(player, citySpawnCF(player, s), "city")
		if s then s.city = s.city or { litter = {}, plots = {}, nextId = 1, jobsDone = 0 } end
		return
	end
	if activity == "hub" and was == "city" then
		player:SetAttribute("Driving", nil)
		player:SetAttribute("CityPose", nil)
		placeCharacter(player, CFrame.new(Places.HUB + Places.HubReturnFromCity + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, math.pi, 0), "hub")
		return
	end
	local c = player.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	if activity == "hub" and hrp and typeof(where) == "string" then
		local spot = where == "house" and Places.HubReturnFromRun or Places.HubSpawn
		c:PivotTo(CFrame.new(Places.HUB + spot + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, math.pi, 0))
	end
end)

-- coins/xp for non-runner modes, capped by how long the round really took
local function grant(player, coins, xp, fn, elapsed)
	local s = sessions[player]
	if not s then return nil end
	local cap = (elapsed or 0) * 3 + 300
	coins = math.floor(math.clamp(math.floor(coins), 0, cap) * passCoinMult(s))
	xp = math.clamp(math.floor(xp), 0, cap * 2)
	local d = s.data
	local oldLevel = d.Level
	d.Coins += coins
	d.TotalCoins += coins
	d.XP += xp
	d.Level = Config.LevelFromXP(d.XP)
	local winsBefore = d.SurvivalWins or 0
	if fn then fn(d) end
	if (d.SurvivalWins or 0) > winsBefore then lbSubmit("wins", player.UserId, d.SurvivalWins) end
	task.spawn(save, player)
	return { coinsEarned = coins, xpEarned = xp, levelUp = d.Level > oldLevel, data = publicData(s) }
end

---------------------------------------------------------------------------
-- LIFECYCLE
---------------------------------------------------------------------------
local function onJoin(player)
	local data, saveable = load(player)
	if not player.Parent then return end
	local studioMaps
	if RunService:IsStudio() and Config.StudioUnlockMaps then
		studioMaps = {}
		for _, m in Config.Maps do
			if not data.OwnedMaps[m.id] then
				data.OwnedMaps[m.id] = true
				studioMaps[m.id] = true
			end
		end
	end
	sessions[player] = { data = data, saveable = saveable, run = nil, lastCall = {}, studioMaps = studioMaps }
	assignHouse(player, sessions[player])
	feed(player.DisplayName .. " sat down at the table", "join")
	syncLook(player, sessions[player])
	if Config.CapsulesArePaid then
		task.spawn(function()
			sessions[player].capsulesRestricted = paidRandomRestricted(player)
		end)
	end
	task.spawn(grantMapPasses, player)
	task.spawn(refreshPasses, player)
	player.CharacterAdded:Connect(function(c)
		-- the client draws the Sminski rig itself; Roblox's default Animate
		-- script only spams "AnimationTrack limit" warnings on this rig
		task.defer(function()
			local anim = c:FindFirstChild("Animate")
			if anim then anim:Destroy() end
		end)
		local hum = c:WaitForChild("Humanoid", 5)
		if not hum then return end
		hum.Died:Connect(function()
			task.wait(1.2)
			if player.Parent and player:GetAttribute("Activity") ~= "park" then
				local act = player:GetAttribute("Activity") or "city"
				if act == "city" then
					placeCharacter(player, citySpawnCF(player, sessions[player]), "city")
				else
					placeCharacter(player, hubSpawnCF * CFrame.new(math.random(-7, 7), 0, math.random(-5, 5)), act)
				end
			end
		end)
	end)
	placeCharacter(player, citySpawnCF(player, sessions[player]), "city")
end

Players.PlayerAdded:Connect(onJoin)
for _, p in Players:GetPlayers() do
	task.spawn(onJoin, p)
end

Players.PlayerRemoving:Connect(function(player)
	writeNow(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	local threads = {}
	for player in sessions do
		table.insert(threads, task.spawn(writeNow, player))
	end
	task.wait(3)
end)

---------------------------------------------------------------------------
-- COALESCED SAVES, PART TWO. See pay()'s `defer` argument and flushPay().
--
-- Only the collect events defer, because only they pay the same player
-- dozens of times in one minute. This loop is what actually writes for them:
-- at most one save per player per PAY_FLUSH seconds, instead of one per
-- item. The two handlers above are the belt and braces -- a player who
-- collects twenty balloons and quits is saved by PlayerRemoving, and a
-- server that shuts down mid-event is saved by BindToClose, both
-- unconditionally -- so the only exposure is a hard crash, which was never
-- protected for anybody.
---------------------------------------------------------------------------
local PAY_FLUSH = 10
task.spawn(function()
	while true do
		task.wait(PAY_FLUSH)
		-- flushPay yields at UpdateAsync, so task.spawn returns before it can
		-- touch `sessions`; nothing mutates the table under this loop
		for player, s in sessions do
			if (s.paySeq or 0) ~= (s.paySaved or 0) then
				task.spawn(flushPay, player, s)
			end
		end
	end
end)

-- multiplayer: lobbies, matchmaking, matches, Elo
-- Dog Park Survival (free-roam, last Sminski alive)
require(script:WaitForChild("Survival"))({
	Config = Config,
	sessions = sessions,
	grant = grant,
	bump = bump,
	feed = feed,
	placeCharacter = placeCharacter,
	freeze = freeze,
})

require(script:WaitForChild("Matchmaking"))({
	Config = Config,
	sessions = sessions,
	session = session,
	publicData = publicData,
	save = save,
	award = award,
	feed = feed,
})

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_EVERY)
		for player in sessions do
			task.spawn(save, player)
		end
	end
end)

-- refresh the lobby leaderboards: the stored all-time top 10, merged with
-- whoever is on this server right now (so a fresh best shows up immediately,
-- and the board still works where DataStores are unavailable)
task.spawn(function()
	while true do
		local out = {}
		for id in LB_DEFS do
			local rows = {}
			local st = lbStores[id]
			if st then
				local ok, pages = pcall(function() return st:GetSortedAsync(false, 10) end)
				if ok and pages then
					for _, e in pages:GetCurrentPage() do
						local uid = tonumber((tostring(e.key):gsub("^u_", "")))
						if uid then rows[uid] = e.value end
					end
				end
			end
			for plr, s in sessions do
				-- BestRankedDistance, NOT BestDistance. This merge is what makes
				-- a fresh best appear without a DataStore round-trip, and it is
				-- also the only other place the board's number comes from -- so
				-- merging the ungated personal best put every run the submit
				-- gate had just refused straight back onto the board, and to a
				-- player nothing was excluded at all.
				local v = id == "distance" and math.floor((s.data.BestRankedDistance or 0) / Config.StudsPerMeter) or (s.data.SurvivalWins or 0)
				if v > 0 and plr.UserId > 0 then rows[plr.UserId] = math.max(rows[plr.UserId] or 0, v) end
			end
			local list = {}
			for uid, v in rows do table.insert(list, { id = uid, v = v }) end
			table.sort(list, function(a, b) return a.v > b.v end)
			local top = {}
			for i = 1, math.min(10, #list) do
				top[i] = { n = lbName(list[i].id), v = list[i].v }
			end
			out[id] = top
		end
		lbValue.Value = HttpService:JSONEncode(out)
		task.wait(60)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	feed(player.DisplayName .. " left the table", "leave")
end)

---------------------------------------------------------------------------
-- SMINSKI CITY: a second way to earn (and spend) the same coins.
--   jobs: deliveries, taxi fares, sweeping litter, farm fields, kart races
--   sinks: cars, businesses (which then earn while you're away), rides, claw
-- Everything is checked against where the player's character really is.
---------------------------------------------------------------------------
do
	local CITY = Places.CITY
	local CC = Config.City
	local lots = Places.cityLots()
	local drops, depot = {}, Places.CityDepot
	for i, l in lots do
		if l.drop then table.insert(drops, i) end
	end
	local farm = Places.cityFarmPlots()
	local RIPE = CC.RipeSeconds
	local CAR_MAX = 130 -- studs/s, a little over the fastest car
	local LITTER = 40
	local raceLen = 0
	do
		local pts = Places.racePoints()
		for i = 1, #pts do raceLen += (pts[i % #pts + 1] - pts[i]).Magnitude end
	end

	local function cityPos(player)
		local c = player.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if not hrp or player:GetAttribute("Activity") ~= "city" then return nil end
		local p = hrp.Position - CITY
		return Vector3.new(p.X, 0, p.Z)
	end
	local function state(s)
		s.city = s.city or { litter = {}, plots = {}, nextId = 1, jobsDone = 0 }
		return s.city
	end
	local function saved(s)
		local d = s.data
		if type(d.City) ~= "table" then d.City = {} end
		local c = d.City
		if type(c.cars) ~= "table" then c.cars = {} end
		c.cars.convertible = true
		if s.passes and s.passes.garage then
			for _, car in Config.City.Cars do c.cars[car.id] = true end
		end
		if type(c.biz) ~= "table" then c.biz = {} end
		if type(c.pantry) ~= "table" then c.pantry = {} end
		c.raceBest = tonumber(c.raceBest) or 0
		-------------------------------------------------------------------
		-- PHASE D: the capsule meter and the Daily 3, back-filled here.
		--
		-- This is the project's lazy-migration point for data.City (it is
		-- why defaultData() and reconcile() know nothing about the city), and
		-- every city entry point calls it, so a save written before phase D
		-- gets its defaults built on the first touch and nothing throws.
		--
		-- `hunt.found` IS A DENSE THREE-ELEMENT BOOLEAN ARRAY AND MUST STAY
		-- ONE. A sparse integer-keyed table is JSON-encoded by the DataStore
		-- as the object {"1":true}, comes back with STRING keys, and a
		-- rejoining player reads found[1] as nil -- 0/3 on the phone, and the
		-- whole day's reward claimable a second time, every session. So it is
		-- rebuilt dense on every load, and the string keys of an already
		-- corrupted save are read back before they are thrown away.
		-------------------------------------------------------------------
		local M, HU = Config.Meter, Config.Hunt
		c.meter = math.clamp(math.floor(tonumber(c.meter) or 0), 0, M.Ticket)
		c.tickets = math.max(0, math.floor(tonumber(c.tickets) or 0))
		c.meterDayTickets = math.max(0, math.floor(tonumber(c.meterDayTickets) or 0))
		if type(c.meterDay) ~= "string" then c.meterDay = "" end
		if (tonumber(c.meterV) or 0) ~= M.Version then
			-- a unit-scale retune loses partial progress and KEEPS the bank
			c.meter = 0
			c.meterV = M.Version
		end
		if type(c.hunt) ~= "table" then c.hunt = {} end
		local h = c.hunt
		if type(h.day) ~= "string" then h.day = "" end
		if type(h.lastFull) ~= "string" then h.lastFull = "" end
		h.streak = math.max(0, math.floor(tonumber(h.streak) or 0))
		-- Only REBUILT when it is not already dense, so the array's identity is
		-- stable after the first touch: this runs on every payout, and a fresh
		-- table each time would silently detach anything holding a reference to
		-- the old one across a saved() call.
		local f = h.found
		local dense = type(f) == "table" and #f == HU.Count
		if dense then
			for i = 1, HU.Count do
				if type(f[i]) ~= "boolean" then dense = false break end
			end
		end
		if not dense then
			local raw = type(f) == "table" and f or {}
			local built = {}
			for i = 1, HU.Count do
				built[i] = (raw[i] == true) or (raw[tostring(i)] == true)
			end
			h.found = built
		end
		return c
	end
	-- litter sits on the roads (always open ground)
	-- WORLD JOBS. Taxi, deliveries, tidy-up and the fields were in the city
	-- long before the Job Center existed, and they still pay exactly the way
	-- they always did. What clocking in adds is that the work now COUNTS: the
	-- shift totals it, reputation moves, streaks run. The Job Center indexes
	-- and dignifies those loops rather than replacing them -- which is the
	-- whole reason they are `world` jobs in Config and not rebuilt minigames.
	-- Assigned further down, where jobs() and publicJobs() exist.
	local creditWorld
	local function newLitter(st)
		local roads = Places.CityRoads
		local r = roads[math.random(1, #roads)]
		local along = math.random(-880, 880)
		local off = math.random(-14, 14)
		local p = math.random() < 0.5 and Vector3.new(r + off, 0, along) or Vector3.new(along, 0, r + off)
		local id = st.nextId
		st.nextId += 1
		st.litter[id] = p
		return id
	end
	-----------------------------------------------------------------------
	-- THE CAPSULE TICKET METER (phase D). One unit per BASE coin, from a
	-- whitelist of stat tags, clamped to Config.Meter.PerMin units a rolling
	-- minute. Ten minutes of real work is one ticket and nothing goes faster.
	--
	-- DECLARED HERE, BETWEEN saved() AND pay(), ON PURPOSE. A `local
	-- function` is invisible to every line above it -- six bugs on this
	-- project have had exactly that shape -- and pay() is the only caller.
	--
	-- The CityEvent push lives in the events block a thousand lines below, so
	-- it gets a forward slot rather than a reach-around: the hunt fills it in.
	-----------------------------------------------------------------------
	local pushTicket -- (player, tickets, meter, from) -> CityEvent("ticket")

	-- THE METER'S IDEA OF "TODAY", AND THE ONE PLACE A TEST CAN MOVE IT.
	--
	-- DayCap is per UTC day, so once a day's grants are consumed the grant path
	-- is unreachable until midnight -- which made CONTRACT section 6.4 (prove
	-- the caps bind) and the from = "meter" animation mutually exclusive on any
	-- given real day, and made rollMeterDay() itself unverifiable. The hunt
	-- already had a `pinned` day for exactly this reason; the meter did not, and
	-- that asymmetry was the whole bug.
	--
	-- So the shift is applied HERE, inside the production function, rather than
	-- by a hook writing meterDay/meterDayTickets directly. A hook that faked the
	-- rollover would prove nothing about the rollover; moving the clock makes
	-- the real rollMeterDay() run for real, which is the same reason the
	-- meterAdd hook fast-forwards the allowance instead of writing c.meter.
	--
	-- devDayShift is assigned in exactly ONE place, inside the
	-- RunService:IsStudio() guard in the hunt block, so in production it is 0
	-- and this is the single os.date call it always was. It deliberately does
	-- NOT move refreshChallenges() or refreshLogin(), which read the date for
	-- themselves: shifting those would corrupt challenge and login-streak state
	-- that has nothing to do with phase D.
	local devDayShift = 0
	local function utcDay()
		if devDayShift ~= 0 then
			return os.date("!%Y-%m-%d", math.floor(os.time()) + devDayShift * 86400)
		end
		return os.date("!%Y-%m-%d")
	end

	-- THE DAY CAP'S ROLLOVER, IN ONE PLACE, RECOMPUTED AND NEVER CACHED.
	--
	-- meterDayTickets only means anything next to the day it was counted on,
	-- so the pair is rolled together and the rule lives here rather than being
	-- copied into each caller. Every path that can READ or MOVE the cap calls
	-- this first -- meterAdd() before it tests the cap, grantTicket() before it
	-- increments, and the hunt's rollover broadcast -- so there is no path on
	-- which a stale meterDay can keep a player capped into the next day.
	--
	-- The same key as refreshChallenges() (:110) and c.dayEnds, deliberately:
	-- UTC midnight is already this game's day boundary in three places and
	-- phase D does not invent a fourth convention.
	local function rollMeterDay(s)
		local c = saved(s)
		local day = utcDay()
		if c.meterDay == day then return false end
		c.meterDay = day
		c.meterDayTickets = 0
		return true
	end

	-- ONE GRANT, ONE WRITE. 400 coins of value must not be lost to a crash,
	-- and this is at most a handful of extra writes per player-hour. Both
	-- sources come through here, so DayCap counts both of them.
	local function grantTicket(player, s, from)
		local c = saved(s)
		rollMeterDay(s)
		c.tickets += 1
		c.meterDayTickets += 1
		if pushTicket then pushTicket(player, c.tickets, c.meter, from) end
		task.spawn(save, player)
		return c.tickets
	end

	-- THE ALLOWANCE IS A CEILING, NOT A CURRENCY. It regenerates with wall
	-- time and is spent only by an action, so standing still accrues
	-- allowance and never accrues units -- that distinction is the whole
	-- anti-AFK design. A rejoin hands you a full burst, which buys nothing:
	-- you still have to do 187 base coins of work to spend it.
	--
	-- The meter itself NEVER writes the save. It moves dozens of times a
	-- minute and pay()'s own `defer`/flushPay already decide when a write
	-- happens; only a ticket grant forces one.
	local function meterAdd(player, s, units)
		local M = Config.Meter
		units = math.floor(tonumber(units) or 0)
		if units <= 0 then return end
		local t = os.clock() -- the same clock allow() uses
		s.meterAllow = math.min(M.Burst, (s.meterAllow or M.Burst) + (t - (s.meterT or t)) * M.PerMin / 60)
		s.meterT = t
		local credit = math.min(units, math.floor(s.meterAllow))
		if credit <= 0 then return end
		s.meterAllow -= credit
		local c = saved(s)
		-- the day is rolled BEFORE the cap is tested, so a player who hit
		-- DayCap yesterday is not still capped on their first payout today
		rollMeterDay(s)
		-- AT EITHER CAP THE METER STOPS AND CREDITED UNITS ARE DISCARDED.
		--
		-- Say it plainly, because the shape of this branch invites a wrong
		-- reading: the clamp below only ever lowers c.meter, and the grant loop
		-- has already drained it below Ticket, so in every reachable state this
		-- is a no-op and the meter simply holds whatever remainder it had.
		-- Units credited from here until something un-caps are GONE -- not
		-- banked, not queued, not "at most one unit lost".
		--
		-- That is the design and it must not be "fixed" into a banking meter. A
		-- DayCap that carried progress forward would let an account accumulate
		-- ten hours of units and cash them out the next day, which is the exact
		-- thing the cap exists to prevent; and MaxTickets exists to force the
		-- trip to the mall, which banking would let a player defer forever.
		--
		-- The two caps un-cap differently, which is worth knowing:
		--   MaxTickets -> redeem one at Capsule Corner and the next payout
		--                 grants again immediately.
		--   DayCap     -> only the UTC rollover, via rollMeterDay() above.
		-- Neither resets c.meter. A capped player carries their sub-ticket
		-- remainder (0..Ticket-1) into tomorrow, which is earned progress that
		-- was simply never converted -- only meterDayTickets is per-day.
		if c.tickets >= M.MaxTickets or c.meterDayTickets >= M.DayCap then
			c.meter = math.min(c.meter, M.Ticket - 1)
			return
		end
		c.meter += credit
		-- grantTicket() moves meterDayTickets, so this cannot spin. With the
		-- shipped numbers it runs at most once per call (Burst 187 << Ticket
		-- 1870, and c.meter was already below Ticket), so the clamp after it is
		-- a belt for the day somebody raises Burst above Ticket -- not a live
		-- path today.
		while c.meter >= M.Ticket and c.tickets < M.MaxTickets and c.meterDayTickets < M.DayCap do
			c.meter -= M.Ticket
			grantTicket(player, s, "meter")
		end
		if c.meter >= M.Ticket then c.meter = M.Ticket - 1 end
	end

	-- `defer` IS FOR ONE KIND OF CALLER AND YOU ARE PROBABLY NOT IT.
	--
	-- Every other caller pays once for one thing -- a job task, a fare, a
	-- found pup -- so writing the save on the spot is correct, and that stays
	-- the default. A COLLECT event is the exception: a player sweeping a
	-- scatter of 48 items calls this dozens of times in a minute, and the
	-- DataStore write budget is roughly 60 + 10 per player per minute for the
	-- WHOLE server. Passing `defer` marks the session dirty instead and the
	-- flush loop beside PlayerRemoving does the writing. Nothing is lost that
	-- way: leaving, the server closing, leaving the city, and the event's own
	-- finish all write unconditionally.
	local function pay(player, s, coins, xp, stat, defer)
		local d = s.data
		-- PHASE D: the capsule meter is credited from the BASE amount, read
		-- here before a single multiplier touches it. That is what makes the
		-- coin passes, the boosts and the login streak meter-neutral.
		local base = coins
		if stat ~= "BizCollects" and s.passes and s.passes.citypro then coins *= Config.Pass("citypro").cityJobMult end
		-- passes first, then any boost (personal and server-wide stack)
		coins = math.floor(coins * passCoinMult(s) * boostMult(player, s))
		d.Coins += coins
		d.TotalCoins += coins
		d.XP += xp
		local old = d.Level
		d.Level = Config.LevelFromXP(d.XP)
		bump(d, "coins", coins)
		if stat then d[stat] = (d[stat] or 0) + 1 end
		if d.Level > old then feed(player.DisplayName .. " reached level " .. d.Level, "level") end
		if defer then
			-- a counter, not a flag: flushPay() records the value it wrote, so
			-- an item paid while a write is in flight is still queued after it
			s.paySeq = (s.paySeq or 0) + 1
		else
			task.spawn(save, player)
		end
		-- Config.Meter.Rates is a WHITELIST: an absent tag credits nothing, so
		-- BizCollects (both sites), HomeNaps and the claw's untagged payout all
		-- credit zero, and so does any income path added after this line.
		local rate = base > 0 and stat and Config.Meter.Rates[stat]
		if rate then meterAdd(player, s, base * rate) end
		return coins
	end
	local function spend(player, s, price)
		if s.data.Coins < price then return false end
		s.data.Coins -= price
		task.spawn(save, player)
		return true
	end
	local function driving(player)
		return player:GetAttribute("Driving") ~= nil
	end

	local function public(s)
		local st = state(s)
		local c = saved(s)
		local litter = {}
		for id, p in st.litter do litter[tostring(id)] = { p.X, p.Z } end
		local plots = {}
		for i, t0 in st.plots do plots[tostring(i)] = t0 end
		local job = st.job and { lot = st.job.lot, pay = st.job.pay } or nil
		local fare = st.fare and { dest = st.fare.dest, pay = st.fare.pay } or nil
		return {
			litter = litter, plots = plots, job = job, fare = fare, ripe = RIPE, jobsDone = st.jobsDone,
			cars = c.cars, biz = c.biz, pantry = c.pantry, raceBest = c.raceBest, racing = st.race ~= nil, now = os.time(),
			role = c.role, hood = c.hood,
			-- THE WHOLE FARM RECORD, verbatim. The client draws crop stages
			-- with Config.CropStage off exactly the table the server pays
			-- out from, so a field can never look ripe while the server
			-- disagrees.
			farm = type(c.farm) == "table" and c.farm or nil,
			tasks = type(c.tasks) == "table" and c.tasks or {},
			tutorial = c.tutorial == true, tour = c.tour == true, apts = type(c.apts) == "table" and c.apts or {}, homeCar = c.homeCar, sleepReady = (os.time() - (tonumber(c.lastSleep) or 0)) > 20 * 3600,
		}
	end
	local function near(pos, spot, r) return (pos - Vector3.new(spot.X, 0, spot.Z)).Magnitude <= r end

	-- WHAT ONE SHOP OWES YOU RIGHT NOW -> amount, bonus, shiftFinished.
	--
	-- A shop banks coins the whole time it is shut, up to CapMinutes. The
	-- first ShiftMinutes of that are a SHIFT: cash out mid-shift and you get
	-- exactly what has piled up; let the shift finish and the payout comes
	-- with ShiftBonus on top. So "wait a bit longer" is a real decision
	-- instead of the cap being a silent punishment for going to bed.
	local function bizDue(c, b, s)
		local since = c.biz[b.id]
		if not since then return 0, 0, false end
		local ty = s.passes and s.passes.tycoon and Config.Pass("tycoon")
		local elapsed = (os.time() - since) / 60
		local mins = math.min(elapsed, CC.CapMinutes * (ty and ty.bizCapMult or 1))
		local amount = math.floor(b.rate * mins * (ty and ty.bizMult or 1))
		local full = elapsed >= (CC.ShiftMinutes or 20)
		local bonus = full and math.floor(amount * (CC.ShiftBonus or 0)) or 0
		return amount, bonus, full
	end

	-- a2 is the SECOND argument some actions need -- planting is "crop X in
	-- plot i", which does not fit one value. Every caller written before this
	-- passes two arguments and gets a2 = nil, so nothing had to change.
	rf("City").OnServerInvoke = function(player, action, arg, a2)
		local s = session(player)
		if not s or not allow(s, "City", 0.12) then return { ok = false } end
		local st = state(s)
		local c = saved(s)
		if action == "state" then
			local n = 0
			for _ in st.litter do n += 1 end
			for _ = n + 1, LITTER do newLitter(st) end
			return { ok = true, city = public(s) }
		end
		local pos = cityPos(player)
		if not pos then return { ok = false, reason = "you're not in the city" } end

		if action == "drive" then
			-- arg = "carId:color" to get in, nil to get out
			if type(arg) ~= "string" then
				player:SetAttribute("Driving", nil)
				player:SetAttribute("DrivingCar", nil)
				return { ok = true }
			end
			local id, col = string.match(arg, "^(%w+):(%d+)$")
			if not id or not Config.CityCar(id) or not c.cars[id] then return { ok = false, reason = "you don't own that car" } end
			player:SetAttribute("Driving", math.clamp(tonumber(col) or 1, 1, CC.CarColors))
			player:SetAttribute("DrivingCar", id)
			c.car = id
			return { ok = true }
		elseif action == "buyCar" then
			local car = Config.CityCar(tostring(arg))
			if not car then return { ok = false } end
			if not near(pos, Places.CityDealer, 90) then return { ok = false, reason = "buy cars at the Car Dealer" } end
			if c.cars[car.id] then return { ok = false, reason = "you already own it" } end
			if not spend(player, s, car.price) then return { ok = false, reason = "not enough coins" } end
			c.cars[car.id] = true
			feed(player.DisplayName .. " bought a " .. car.name .. " in Sminski City", "info")
			return { ok = true, city = public(s), data = publicData(s) }

		elseif action == "takeJob" then
			if not near(pos, depot, 30) then return { ok = false, reason = "pick parcels up at the Post Office" } end
			if st.job then return { ok = false, reason = "you're already carrying a parcel" } end
			local lot = drops[math.random(1, #drops)]
			local dist = (lots[lot].door - depot).Magnitude
			st.job = { lot = lot, pay = math.floor(CC.Delivery.base + dist * CC.Delivery.perStud), t0 = os.clock(), dist = dist }
			return { ok = true, city = public(s) }
		elseif action == "deliver" then
			local job = st.job
			if not job then return { ok = false } end
			if not near(pos, lots[job.lot].door, 24) then return { ok = false, reason = "that's not the right door" } end
			if os.clock() - job.t0 < job.dist / CAR_MAX then return { ok = false, reason = "too fast!" } end
			st.job = nil
			st.jobsDone += 1
			local got = pay(player, s, job.pay, 12, "Deliveries")
			if creditWorld then creditWorld(player, s, "delivery", 1, got) end
			if st.jobsDone % 5 == 0 then feed(player.DisplayName .. " delivered " .. st.jobsDone .. " parcels in Sminski City", "info") end
			return { ok = true, coins = got, city = public(s), data = publicData(s) }

		elseif action == "takeFare" then
			if not driving(player) then return { ok = false, reason = "you need a car to drive a taxi fare" } end
			if not near(pos, Places.CityTaxiStand, 36) then return { ok = false, reason = "passengers wait at the Taxi Stand" } end
			if st.fare then return { ok = false, reason = "you already have a passenger" } end
			local marks = Places.CityLandmarks
			local pick
			for _ = 1, 20 do
				local i = math.random(1, #marks)
				if (marks[i].pos - Places.CityTaxiStand).Magnitude > 350 then pick = i break end
			end
			pick = pick or 1
			local dist = (marks[pick].pos - Places.CityTaxiStand).Magnitude
			local fare = CC.Taxi.base + dist * CC.Taxi.perStud
			if player:GetAttribute("DrivingCar") == "taxi" then fare *= 1.5 end
			st.fare = { dest = pick, pay = math.floor(fare), t0 = os.clock(), dist = dist }
			return { ok = true, city = public(s) }
		elseif action == "dropFare" then
			local f = st.fare
			if not f then return { ok = false } end
			if not near(pos, Places.CityLandmarks[f.dest].pos, 40) then return { ok = false } end
			if os.clock() - f.t0 < f.dist / CAR_MAX then return { ok = false, reason = "too fast!" } end
			st.fare = nil
			local got = pay(player, s, f.pay, 14, "TaxiFares")
			if creditWorld then creditWorld(player, s, "taxi", 1, got) end
			return { ok = true, coins = got, city = public(s), data = publicData(s) }

		elseif action == "sweep" then
			local id = tonumber(arg)
			local p = id and st.litter[id]
			if not p then return { ok = false } end
			local truck = player:GetAttribute("DrivingCar") == "icecream"
			if (pos - p).Magnitude > (truck and 28 or 18) then return { ok = false } end
			st.litter[id] = nil
			newLitter(st)
			local got = pay(player, s, CC.Sweep + (truck and 2 or 0), 1, "Sweeps")
			if creditWorld then creditWorld(player, s, "cleaner", 1, got) end
			return { ok = true, coins = got, city = public(s), data = publicData(s) }

		elseif action == "plant" or action == "harvest" or action == "water"
			or action == "fert" or action == "sellCrops" then
			-----------------------------------------------------------------
			-- THE FARM (docs/FARMING.md).
			--
			-- WHY THE STATE IS A TIMESTAMP. A plot is
			-- { crop, at, watered, fert } and NOTHING touches it between
			-- planting and harvest -- no heartbeat, no ticking object, no
			-- per-crop thread. Sixty players farming twelve plots each costs
			-- the server zero work per frame, and growth continues while they
			-- are offline for free, because it is arithmetic on `at`.
			--
			-- WHERE IT LIVES. c.farm, which is SAVED, unlike the legacy
			-- st.plots timestamps that were session-only. A five minute crop
			-- has to survive a rejoin; a forty-five second one did not.
			--
			-- ONE DEFINITION OF RIPENESS. Config.CropStage is the only thing
			-- that decides, and the client draws from the same function, so
			-- the field a player is looking at and the field being paid out
			-- can never disagree.
			--
			-- EVERY BRANCH USES THE COALESCED save(). A watering pass over
			-- twelve plots is one DataStore write, not twelve -- see the
			-- rate-limited save() near the top of this file.
			-----------------------------------------------------------------
			c.farm = type(c.farm) == "table" and c.farm or { plots = {}, store = {} }
			local F = c.farm
			F.plots = type(F.plots) == "table" and F.plots or {}
			F.store = type(F.store) == "table" and F.store or {}
			local now = workspace:GetServerTimeNow()

			local function carried()
				local n = 0
				for _, q in pairs(F.store) do n += q end
				return n
			end

			if action == "sellCrops" then
				-- SELLING IS A PHYSICAL DELIVERY. You have to be at a buyer's
				-- door with the produce on you; there is no sell-from-anywhere
				-- menu, because hauling is the half of the job that puts the
				-- farmer in the city.
				local atBuyer = near(pos, Places.CityMarketTill, 40)
				if not atBuyer then
					for _, l in lots do
						if (l.btype == "grocery" or l.btype == "cafe" or l.btype == "restaurant")
							and near(pos, l.door, 40) then atBuyer = true break end
					end
				end
				if not atBuyer then return { ok = false, reason = "sell at a grocery or a kitchen" } end
				local total, n = 0, 0
				for id, qty in pairs(F.store) do
					local cd = Config.Crop(tostring(id))
					qty = math.floor(tonumber(qty) or 0)
					if cd and qty > 0 then total += cd.sell * qty n += qty end
				end
				if n <= 0 then return { ok = false, reason = "nothing to sell" } end
				F.store = {}
				bump(s.data, "cropsSold", n)
				local got = pay(player, s, total, math.max(2, math.floor(n / 2)), "CityHarvests")
				if creditWorld then creditWorld(player, s, "farmhand", 1, got) end
				save(player)
				return { ok = true, coins = got, sold = n, city = public(s), data = publicData(s) }
			end

			local i = tonumber(arg)
			local plot = i and farm[i]
			if not plot or not near(pos, plot, 28) then return { ok = false, reason = "walk up to the field" } end
			if i > Config.Farm.MaxPlots then return { ok = false } end
			local key = tostring(i)
			local rec = F.plots[key]

			if action == "plant" then
				if rec then return { ok = false, reason = "something is already growing there" } end
				local cd = Config.Crop(tostring(a2))
				if not cd then return { ok = false } end
				if s.data.Level < (cd.level or 1) then return { ok = false, reason = "level", level = cd.level } end
				if not spend(player, s, cd.seed) then return { ok = false, reason = "not enough coins" } end
				F.plots[key] = { crop = cd.id, at = now }
				save(player)
				return { ok = true, city = public(s), data = publicData(s) }

			elseif action == "water" or action == "fert" then
				if not rec then return { ok = false, reason = "nothing growing there" } end
				-- A READY CROP CANNOT BE HURRIED, and saying so is kinder than
				-- silently taking the fertiliser money for nothing.
				if Config.CropStage(rec, now) >= Config.Farm.Stages - 1 then
					return { ok = false, reason = "that one is ready already" }
				end
				local field = action == "water" and "watered" or "fert"
				if rec[field] then return { ok = false, reason = "already done" } end
				-- CHARGE ONLY IF IT WILL DO SOMETHING. CropBoost is the one
				-- definition of what water and fertiliser do (Config.lua), so
				-- the client's preview and this payout cannot drift apart.
				if action == "fert" and not spend(player, s, Config.Farm.FertCost) then
					return { ok = false, reason = "not enough coins" }
				end
				Config.CropBoost(rec, field, now)
				save(player)
				return { ok = true, city = public(s), data = publicData(s) }

			end

			-- HARVEST
			if not rec then return { ok = false, reason = "nothing growing there" } end
			if Config.CropStage(rec, now) < Config.Farm.Stages - 1 then
				return { ok = false, reason = "not ripe yet" }
			end
			local cd = Config.Crop(rec.crop)
			local n = math.random(cd.yield[1], cd.yield[2])
			-- CAPACITY IS THE THROTTLE ON FARM INCOME, not the crop price
			-- (docs/FARMING.md section 5). A full store means the trip into
			-- town has to happen before any more is picked, which is the
			-- pacing the job is built around.
			local room = math.max(0, Config.Farm.StartStore - carried())
			if room <= 0 then return { ok = false, reason = "you are carrying all you can -- sell some in town" } end
			n = math.min(n, room)
			F.plots[key] = nil
			F.store[cd.id] = (F.store[cd.id] or 0) + n
			bump(s.data, "harvest", 1)
			s.data.CityHarvests = (s.data.CityHarvests or 0) + 1
			save(player)
			return { ok = true, got = n, crop = cd.id, city = public(s), data = publicData(s) }

		elseif action == "checkout" then
			-- GROCERIES. The basket is client-side until this moment; here it
			-- is priced from Config (never from the client), paid for, and put
			-- in the fridge. You must be standing at a till: the SUPER MARKET's
			-- or a corner grocery's door.
			if type(arg) ~= "table" then return { ok = false } end
			local atTill = near(pos, Places.CityMarketTill, 40)
			if not atTill then
				for _, l in lots do
					if l.btype == "grocery" and near(pos, l.door, 40) then atTill = true break end
				end
			end
			if not atTill then return { ok = false, reason = "pay at the till" } end
			local total, count, lines = 0, 0, {}
			for id, qty in pairs(arg) do
				local g = Config.Grocery(tostring(id))
				qty = math.floor(tonumber(qty) or 0)
				if g and qty > 0 then
					qty = math.min(qty, Config.BasketMax)
					total += g.price * qty
					count += qty
					lines[g.id] = qty
				end
			end
			if count == 0 then return { ok = false, reason = "your basket is empty" } end
			if count > Config.BasketMax then return { ok = false, reason = "that is more than one basket" } end
			local have = 0
			for _, n in pairs(c.pantry) do have += n end
			if have + count > Config.PantryMax then return { ok = false, reason = "your fridge is full -- eat something first" } end
			if not spend(player, s, total) then return { ok = false, reason = "not enough coins" } end
			for id, qty in pairs(lines) do c.pantry[id] = (c.pantry[id] or 0) + qty end
			bump(s.data, "groceries", count)
			return { ok = true, paid = total, count = count, city = public(s), data = publicData(s) }

		elseif action == "eat" then
			-- a snack from your own fridge: one item out, a little XP in.
			-- Which item: the one asked for if you have it, else whatever is
			-- at the front. Being at home is the client's business (the fridge
			-- is the only thing that asks); the stakes are 15 XP.
			local want = type(arg) == "string" and c.pantry[arg] and arg or nil
			if not want then
				for id, n in pairs(c.pantry) do if n > 0 then want = id break end end
			end
			if not want then return { ok = false, reason = "the fridge is empty -- buy groceries at the market" } end
			c.pantry[want] -= 1
			if c.pantry[want] <= 0 then c.pantry[want] = nil end
			pay(player, s, 0, Config.SnackXP, "Snacks")
			return { ok = true, ate = want, city = public(s), data = publicData(s) }

		elseif action == "buyBiz" then
			local b = Config.CityBiz(tostring(arg))
			local spot = b and Places.CityBiz[b.id]
			if not spot then return { ok = false } end
			-- BUYING still means walking there. Collecting does not: that is
			-- what the business card is for.
			if not near(pos, spot, 34) then return { ok = false, reason = "walk up to the shop" } end
			if c.biz[b.id] then return { ok = false, reason = "you already own it" } end
			if not spend(player, s, b.price) then return { ok = false, reason = "not enough coins" } end
			c.biz[b.id] = os.time()
			feed(player.DisplayName .. " bought the " .. b.name .. " in Sminski City!", "rare")
			return { ok = true, city = public(s), data = publicData(s) }

		elseif action == "collectBiz" or action == "collectAllBiz" then
			local list = {}
			if action == "collectBiz" then
				local b = Config.CityBiz(tostring(arg))
				if not b then return { ok = false } end
				if not c.biz[b.id] then return { ok = false, reason = "you don't own this shop yet" } end
				table.insert(list, b)
			else
				for _, b in CC.Businesses do
					if c.biz[b.id] then table.insert(list, b) end
				end
			end
			local total, bonusTotal, shops, anyFull = 0, 0, 0, false
			for _, b in list do
				local amount, bonus, full = bizDue(c, b, s)
				if amount >= 1 then
					c.biz[b.id] = os.time()
					total += amount
					bonusTotal += bonus
					shops += 1
					anyFull = anyFull or full
				end
			end
			if shops == 0 then return { ok = false, reason = "nothing to collect yet" } end
			local got = pay(player, s, total + bonusTotal, math.floor(total / 20), "BizCollects")
			return { ok = true, coins = got, bonus = bonusTotal, full = anyFull, shops = shops,
				city = public(s), data = publicData(s) }

		elseif action == "ride" then
			local id = tostring(arg)
			local price = CC.Rides[id]
			local spot = Places.CityRides[id]
			if not price or not spot then return { ok = false } end
			if not near(pos, spot, 40) then return { ok = false, reason = "walk up to the ride" } end
			if not player:GetAttribute("VIP") and not spend(player, s, price) then return { ok = false, reason = "not enough coins" } end
			return { ok = true, data = publicData(s) }

		elseif action == "claw" then
			if not near(pos, Places.CityClaw, 70) then return { ok = false } end
			if not spend(player, s, CC.Claw.price) then return { ok = false, reason = "not enough coins" } end
			local r = math.random()
			local prize
			if r < 0.08 then
				-- a free capsule
				local res = rollCapsule(player, s)
				prize = { kind = "capsule", character = res.character, rarity = res.rarity, duplicate = res.duplicate }
			elseif r < 0.16 then
				-- an outfit you don't have yet (from the cheaper shop rack)
				local pool = {}
				for _, o in Config.Outfits do
					if o.price > 0 and o.price <= 1000 and not o.exclusive and not s.data.OwnedOutfits[o.id] then table.insert(pool, o) end
				end
				if #pool > 0 then
					local o = pool[math.random(1, #pool)]
					s.data.OwnedOutfits[o.id] = true
					prize = { kind = "outfit", id = o.id, name = o.name }
				end
			end
			if not prize then
				local amt = r < 0.5 and math.random(10, 30) or r < 0.8 and 50 or r < 0.95 and 120 or 250
				local got = pay(player, s, amt, 1)
				prize = { kind = "coins", coins = got }
			end
			task.spawn(save, player)
			return { ok = true, prize = prize, data = publicData(s) }

		-- SPEND A CAPSULE TICKET, AT THE MACHINE, IN THE MALL (phase D).
		--
		-- It lives on this remote and not on OpenCapsule because OpenCapsule
		-- sits at file scope, where cityPos, near and city-relative Places
		-- coordinates are not in scope. Everything needed is already here, and
		-- rollCapsule is a file-level local, so it is in scope too.
		--
		-- IT DELIBERATELY CHECKS NEITHER Config.CapsulesArePaid NOR
		-- s.capsulesRestricted, and that omission must not be "fixed". The
		-- policy covers PAID random items; a ticket costs no Robux and not even
		-- coins, and a free-play route to a random item is the first remedy the
		-- policy itself points restricted players at. The paid path at
		-- OpenCapsule keeps its check, unchanged.
		elseif action == "capsuleTicket" then
			local corner
			for _, sh in Places.MallShops do
				if sh.id == "capsules" then corner = sh break end
			end
			if c.tickets < 1 then return { ok = false, reason = "no capsule tickets yet" } end
			if not corner or not near(pos, corner.pos, Config.Meter.RedeemServer) then
				return { ok = false, reason = "use tickets at Capsule Corner in the mall" }
			end
			----- no yield from here ------------------------------------------
			-- DECREMENT BEFORE THE ROLL, NEVER AFTER: rollCapsule spawns a save
			-- of its own, and a write landing between the roll and the
			-- decrement would persist a spent ticket as unspent. Nothing yields
			-- between the check above and this line either, so two calls in one
			-- frame cannot both get past it.
			c.tickets -= 1
			----- to here -----------------------------------------------------
			local res = rollCapsule(player, s)
			res.tickets, res.meter = c.tickets, c.meter
			-- `data` COMES BACK OR THE ANIMATION IS WRONG. rollCapsule already
			-- puts publicData(s) in here, and it builds it after the duplicate
			-- refund, so the two are identical -- it is set again explicitly
			-- because UI.playCapsule() applies res.data at +1.6s, which is what
			-- makes the ticket count drop while the capsule is still shaking. If
			-- rollCapsule ever stops returning it, this line is why the client
			-- still works.
			res.data = publicData(s)
			res.city = public(s)
			task.spawn(save, player)
			return res

		elseif action == "raceStart" then
			if not driving(player) then return { ok = false, reason = "drive onto the track to race" } end
			if not near(pos, Places.RaceStart, 36) then return { ok = false } end
			if not spend(player, s, CC.Race.entry) then return { ok = false, reason = "not enough coins" } end
			st.race = { t0 = os.clock() }
			return { ok = true, city = public(s), data = publicData(s) }
		elseif action == "raceFinish" then
			local race = st.race
			if not race then return { ok = false } end
			if not near(pos, Places.RaceStart, 40) then return { ok = false } end
			local t = os.clock() - race.t0
			if t < raceLen * Places.RaceLaps / CAR_MAX then return { ok = false, reason = "too fast!" } end
			st.race = nil
			local R = CC.Race
			local amount = t <= R.gold and R.goldPay or t <= R.par and R.parPay or R.finishPay
			local best = c.raceBest
			local record = best == 0 or t < best
			if record then c.raceBest = math.floor(t * 100) / 100 end
			local got = pay(player, s, amount, 6, "Races")
			if t <= R.gold then feed(player.DisplayName .. " won GOLD at the Kart Track (" .. string.format("%.1f", t) .. "s)", "rare") end
			return { ok = true, coins = got, time = t, record = record, medal = t <= R.gold and "gold" or t <= R.par and "silver" or "bronze", city = public(s), data = publicData(s) }
		elseif action == "tutorialDone" then
			c.tutorial = true
			task.spawn(save, player)
			return { ok = true, city = public(s) }
		elseif action == "buyApt" then
			-- arg = "building:plan". No position check: the leasing desk is in an
			-- instanced lobby far from the street door. The price comes from
			-- Config on THIS side -- the client only names what it wants.
			local bid, pid = string.match(tostring(arg), "^(%w+):(%w+)$")
			local b, p = Config.AptBuilding(bid or ""), Config.AptPlan(pid or "")
			if not b or not p then return { ok = false } end
			if type(c.apts) ~= "table" then c.apts = {} end
			if c.apts[b.id] == p.id then return { ok = false, reason = "that one is already yours" } end
			if not spend(player, s, Config.AptPrice(b, p)) then return { ok = false, reason = "not enough coins" } end
			c.apts[b.id] = p.id
			feed(player.DisplayName .. " moved into a " .. string.lower(p.name) .. " at " .. b.name, "info")
			task.spawn(save, player)
			return { ok = true, city = public(s), data = publicData(s) }
		elseif action == "pose" then
			-- THE ONLY WAY ANOTHER PLAYER SEES YOU SIT. Positions replicate on
			-- their own (real characters), but a pose is drawn client-side from
			-- Hub.updateAvatars, so it has to be published like "Driving" is or
			-- everyone at a hangout looks like they are standing up.
			local pose = tostring(arg or "")
			if pose == "" or pose == "none" then
				player:SetAttribute("CityPose", nil)
			else
				player:SetAttribute("CityPose", string.sub(pose, 1, 12))
			end
			return { ok = true }
		elseif action == "tourDone" then
			-- the welcome tour (CityGuide): shown once, replayable from the HUD
			c.tour = true
			task.spawn(save, player)
			return { ok = true, city = public(s) }
		elseif action == "task" then
			-------------------------------------------------------------
			-- CITY TASKS (docs/ONBOARDING.md section 5, Config.Tasks).
			--
			-- The client asks "what now?" and gets exactly one task back,
			-- with its progress. THE ANSWER IS NEVER EMPTY while work
			-- remains -- an empty goal widget is the "what do I do?"
			-- problem coming straight back, which is the whole reason this
			-- exists.
			--
			-- CLAIMING IS SERVER-CHECKED against the same lifetime counters
			-- bump() writes, so a client cannot claim a reward for a task
			-- it has not done.
			-------------------------------------------------------------
			c.tasks = type(c.tasks) == "table" and c.tasks or {}
			-- TWO COUNTER SYSTEMS, ONE LOOKUP. pay() writes PascalCase totals
			-- straight onto the save (Sweeps, JobTasks, HomeNaps); bump()
			-- writes lowercase lifetime counters into d.Stats. Rather than
			-- migrate forty call sites, a task's `stat` is resolved against
			-- both -- and against the derived states in Config.TaskDerived,
			-- which are answers to "how many do you have" rather than counts
			-- of things that happened.
			local d = s.data
			local lifetime = type(d.Stats) == "table" and d.Stats or {}
			local function countOf(tbl)
				local n = 0
				for _ in pairs(type(tbl) == "table" and tbl or {}) do n += 1 end
				return n
			end
			local derived = {
				roleSet = c.role and 1 or 0,
				carsOwned = countOf(c.cars),
				aptsOwned = countOf(c.apts),
			}
			local stats = setmetatable({}, { __index = function(_, k)
				if Config.TaskDerived[k] then return derived[k] or 0 end
				return lifetime[k] or d[k] or 0
			end })

			if arg == "claim" then
				local t = Config.Task(tostring(a2))
				if not t or c.tasks[t.id] then return { ok = false } end
				if not Config.TaskReady(t, c.tasks) then return { ok = false } end
				if (stats[t.stat] or 0) < t.goal then return { ok = false, reason = "not finished yet" } end
				c.tasks[t.id] = true
				local got = 0
				if (t.reward or 0) > 0 or (t.xp or 0) > 0 then
					got = pay(player, s, t.reward or 0, t.xp or 0, nil)
				end
				save(player)
				return { ok = true, coins = got, city = public(s), data = publicData(s) }
			end

			local t, progress = Config.NextTask(c.tasks, stats)
			if not t then return { ok = true, task = nil } end
			return { ok = true, task = { id = t.id, text = t.text, how = t.how,
				reward = t.reward, xp = t.xp, track = t.track,
				have = progress, need = t.goal,
				ready = (stats[t.stat] or 0) >= t.goal } }

		elseif action == "role" then
			-------------------------------------------------------------
			-- PICK A ROLE, OR CHANGE YOUR MIND.
			--
			-- The first pick is FREE and happens before the city loads.
			-- Every later one costs Config.RoleSwitchCost -- enough that it
			-- reads as a decision, cheap enough that nobody is stuck with a
			-- choice they made knowing nothing.
			--
			-- A ROLE IS A SPAWN AND A FIRST JOB, NOT A CLASS. It gates
			-- nothing: every job in Config.Jobs stays open to everybody
			-- whatever this says, so there is no permission to check here
			-- and no career to migrate.
			--
			-- SWITCHING DOES NOT MOVE YOU. `hood` is written on the first
			-- pick only. By the time anyone switches they live somewhere
			-- they chose, and relocating them would be taking it away.
			-------------------------------------------------------------
			local role = type(arg) == "string" and Config.Role(arg)
			if not role then return { ok = false } end
			-------------------------------------------------------------
			-- PRE-GROWN LAND. A new farmer's parcel does not start bare.
			--
			-- The crops in docs/FARMING.md take five to twelve minutes,
			-- which is right for a farm and wrong for somebody's first two
			-- minutes: the ten-step first session (FARMING.md section 6)
			-- reaches HARVEST long before a carrot they planted themselves
			-- could be ready. So two plots arrive already ripe. They learn
			-- prepare/plant/water on an empty plot, harvest a ready one
			-- immediately, and meet the real timer on the second planting
			-- -- by which point they have been paid once and have a reason
			-- to wait.
			--
			-- The alternative was shortening the carrot for everybody to
			-- fix the first two minutes, which would have cost the job its
			-- whole shape.
			--
			-- THESE PLOTS PERSIST, unlike the legacy st.plots timestamps in
			-- the session: a five-minute crop has to keep growing while you
			-- are offline, so the record lives in the save.
			-------------------------------------------------------------
			local function seedStarterFarm()
				if type(c.farm) == "table" then return end
				local now = workspace:GetServerTimeNow()
				local carrot = Config.Crop("carrot")
				c.farm = { plots = {}, store = {} }
				for _, i in { 2, 3 } do
					c.farm.plots[tostring(i)] = { crop = "carrot", at = now - carrot.grow, watered = true }
				end
			end
			if c.role == role.id then return { ok = true, city = public(s) } end
			local first = c.role == nil
			if not first then
				if not spend(player, s, Config.RoleSwitchCost) then
					return { ok = false, reason = "not enough coins" }
				end
			end
			c.role = role.id
			if first then c.hood = role.hood end
			if role.id == "farmer" then seedStarterFarm() end
			task.spawn(save, player)
			return { ok = true, first = first, city = public(s), data = publicData(s) }
		elseif action == "homeBonus" then
			-- a good night's sleep at home: once a day
			if (os.time() - (tonumber(c.lastSleep) or 0)) < 20 * 3600 then return { ok = true, rested = false } end
			local house = player:GetAttribute("CityHouse")
			if not house then return { ok = false } end
			c.lastSleep = os.time()
			local got = pay(player, s, 50 * ((s.passes and s.passes.greenthumb) and Config.Pass("greenthumb").sleepMult or 1), 10, "HomeNaps")
			return { ok = true, rested = true, coins = got, city = public(s), data = publicData(s) }
		elseif action == "parkHome" then
			local id = type(arg) == "string" and string.match(arg, "^(%w+):%d+$")
			if not id or not c.cars[id] then return { ok = false } end
			local house = player:GetAttribute("CityHouse")
			local lot = house and lots[house]
			if not lot or not near(pos, lot.door, 60) then return { ok = false } end
			c.homeCar = arg
			task.spawn(save, player)
			return { ok = true, city = public(s) }
		elseif action == "raceQuit" then
			st.race = nil
			return { ok = true, city = public(s) }
		end
		return { ok = false }
	end

	---------------------------------------------------------------------------
	-- THE TOWN DIRECTORY: who is on this server, where they live, what they
	-- own, and who has the most.
	--
	-- Nothing here is a new disclosure. A house is a numbered door on a public
	-- street that anyone can already walk up to and knock on; an owned shop
	-- already has its owner standing in it. This is an index of the world, not
	-- a leak of it -- which is also why it is THIS SERVER ONLY: it is about the
	-- people you are actually sharing a town with.
	---------------------------------------------------------------------------
	rf("Town").OnServerInvoke = function(player)
		local s = session(player)
		if not s or not allow(s, "Town", 0.5) then return { ok = false } end
		local rows = {}
		for plr, ss in sessions do
			if ss.data and plr.Parent then
				local c = saved(ss)
				local biz = {}
				for _, b in CC.Businesses do
					if c.biz[b.id] then table.insert(biz, b.id) end
				end
				-- where they live, and the door to send you to
				local where, door
				local apts = type(c.apts) == "table" and c.apts or {}
				for bid, planId in apts do
					local bd, pl = Config.AptBuilding(bid), Config.AptPlan(planId)
					if bd and pl then
						where = { kind = "apt", name = bd.name, sub = pl.name }
						local d = Places.aptDoor(bid)
						if not d then
							-- Places.CityApts only holds the three TOWER sites. The
							-- brownstones and the townhouses are not sites at all --
							-- they are lots that already stand on the street -- so
							-- their door comes from the first lot of that kind.
							-- A lease is per building, not per unit, so any of its
							-- doors is the right place to send a visitor.
							local want = (bid == "mochi" and "apartment") or (bid == "willow" and "rowhouse") or nil
							if want then
								for _, l in lots do
									if l.kind == want then d = l.door or l.pos break end
								end
							end
						end
						if d then door = { d.X, d.Z } end
						break
					end
				end
				if not where then
					local lot = lots[plr:GetAttribute("CityHouse")]
					if lot then
						where = { kind = "house", name = lot.address, sub = "a house on the street" }
						door = { lot.door.X, lot.door.Z }
					end
				end
				table.insert(rows, {
					name = plr.DisplayName, userId = plr.UserId,
					coins = ss.data.Coins or 0, level = ss.data.Level or 1,
					vip = plr:GetAttribute("VIP") == true,
					me = plr == player,
					where = where, door = door, biz = biz,
				})
			end
		end
		return { ok = true, rows = rows }
	end

	---------------------------------------------------------------------------
	-- RESTAURANT ROW: the tycoon (docs/TYCOON.md). Config.Tycoon has the
	-- design; this is the money.
	--
	-- WHO OWNS WHAT. The RESTAURANT is in the owner's save (data.City.tycoon:
	-- pieces, stock, till, stars, chains). The LOT is per server, claimed at a
	-- gate the way a house is assigned (assignHouse): tyOwner[i] = player for
	-- as long as they are here, released on PlayerRemoving. Every client
	-- draws every claimed lot from the attributes on
	-- ReplicatedStorage.SminskiTycoon.Lot<i> -- Owner, Name, Pieces, Stars,
	-- Open -- so a friend's restaurant is a handful of strings, not a remote.
	--
	-- THE MONEY IS SETTLED LAZILY, the way a shop banks (bizDue): nothing
	-- ticks. tyDue() replays what the kitchen would have sold since `since`
	-- -- so many orders a minute, round-robin over the dishes it can make,
	-- each one eating its ingredients out of a COPY of the stock -- and stops
	-- when the stockroom is bare. settle() writes that result back (stock
	-- down, bank up, since = now) before any state change that would alter
	-- the replay: buying a piece, restocking, a friend's order. That is what
	-- stops "restock, then collect" counting the new stock as if it had been
	-- there all along.
	--
	-- TWO POTS. `bank` is passive takings: bonus-eligible, like a shop's
	-- shift. `till` is what friends paid at the counter and the tip jar:
	-- their coins, moved, never multiplied. Both are paid out by COLLECT at
	-- the register, and by AUTO-COLLECT when the shift has finished.
	---------------------------------------------------------------------------
	local TY = Config.Tycoon
	local tyLots = Places.tycoonLots()
	local tyOwner, tyLotOf = {}, {} -- [lotIndex] = player, [player] = lotIndex
	local tyFolder = Instance.new("Folder")
	tyFolder.Name = "SminskiTycoon"
	tyFolder.Parent = ReplicatedStorage
	local tyCfg = {}
	for i in tyLots do
		local cfg = Instance.new("Configuration")
		cfg.Name = "Lot" .. i
		cfg:SetAttribute("Owner", 0)
		cfg:SetAttribute("OwnerName", "")
		cfg:SetAttribute("Name", "")
		cfg:SetAttribute("Pieces", "")
		cfg:SetAttribute("Stars", 1)
		cfg:SetAttribute("Open", false)
		cfg:SetAttribute("Chains", 0)
		cfg:SetAttribute("Gold", false)
		cfg.Parent = tyFolder
		tyCfg[i] = cfg
	end
	-- to the owner: "X ordered a Noodle Bowl at your place" and the like
	local tyEvent = Instance.new("RemoteEvent")
	tyEvent.Name = "TycoonEvent"
	tyEvent.Parent = remotes

	-- the saved restaurant, defaults back-filled (the lazy migration, as saved())
	local function tycoon(c)
		if type(c.tycoon) ~= "table" then c.tycoon = {} end
		local t = c.tycoon
		if type(t.pieces) ~= "table" then t.pieces = {} end
		if type(t.stock) ~= "table" then t.stock = {} end
		for k, v in pairs(t.stock) do
			v = math.floor(tonumber(v) or 0)
			if v <= 0 or not Config.Grocery(k) then t.stock[k] = nil else t.stock[k] = v end
		end
		t.bank = math.max(0, math.floor(tonumber(t.bank) or 0))
		t.till = math.max(0, math.floor(tonumber(t.till) or 0))
		t.since = tonumber(t.since) or os.time()
		t.shift = tonumber(t.shift) or t.since
		t.xp = math.max(0, math.floor(tonumber(t.xp) or 0))
		t.chains = math.max(0, math.floor(tonumber(t.chains) or 0))
		t.served = math.max(0, math.floor(tonumber(t.served) or 0))
		t.sold = math.max(0, math.floor(tonumber(t.sold) or 0))
		t.sales = math.max(0, math.floor(tonumber(t.sales) or 0))
		t.rushUntil = tonumber(t.rushUntil) or 0
		if type(t.name) ~= "string" or t.name == "" then t.name = nil end
		return t
	end
	local function tyStockCap(t, s)
		local cap = t.pieces.stockroom and TY.StockroomMax or TY.StockMax
		local rp = s.passes and s.passes.restaurateur and Config.Pass("restaurateur")
		if rp then cap *= rp.tycoonStockMult or 1 end
		return cap
	end
	local function tyStockCount(stock)
		local n = 0
		for _, q in pairs(stock) do n += q end
		return n
	end
	local function tyMaxChains(s)
		local rp = s.passes and s.passes.restaurateur and Config.Pass("restaurateur")
		return TY.Chain.max + (rp and rp.tycoonChains or 0)
	end
	-- sales/min, with stars and chains on top of the pieces
	local function tyRate(t)
		local stars = Config.TycoonStars(t.xp)
		return Config.TycoonBaseRate(t.pieces) * (1 + (stars - 1) * TY.StarRate) * (1 + t.chains * TY.Chain.rate)
	end
	local function canCook(stock, m)
		for _, gid in m.needs do
			if (stock[gid] or 0) < 1 then return false end
		end
		return true
	end
	local function consume(stock, m)
		for _, gid in m.needs do
			stock[gid] -= 1
			if stock[gid] <= 0 then stock[gid] = nil end
		end
	end
	-- WHAT IT SOLD SINCE `since`. Pure: returns coins (pass applied), orders,
	-- the stock as it would be afterwards, and whether it ran dry.
	local function tyDue(t, s)
		local menu = Config.TycoonMenuFor(t.pieces)
		if #menu == 0 then return 0, 0, t.stock, false end
		local ty = s.passes and s.passes.tycoon and Config.Pass("tycoon")
		local now = os.time()
		local mins = math.min((now - t.since) / 60, CC.CapMinutes * (ty and ty.bizCapMult or 1))
		if mins <= 0 then return 0, 0, t.stock, false end
		-- RUSH HOUR: the minutes it covered count `mult` times over
		local rush = 0
		if t.rushUntil > t.since then
			local rp = Config.Product("tycoonrush")
			rush = math.min(mins, (math.min(now, t.rushUntil) - t.since) / 60) * ((rp and rp.mult or 3) - 1)
		end
		local avg = 0
		for _, m in menu do avg += m.price end
		avg /= #menu
		local orders = math.floor((mins + rush) * tyRate(t) / avg)
		local stock = table.clone(t.stock)
		local coins, cooked, k, dry = 0, 0, 0, false
		while cooked < orders do
			local any = false
			for _ = 1, #menu do
				k = k % #menu + 1
				local m = menu[k]
				if canCook(stock, m) then
					consume(stock, m)
					coins += m.price
					cooked += 1
					any = true
					if cooked >= orders then break end
				end
			end
			if not any then dry = true break end
		end
		return math.floor(coins * (ty and ty.bizMult or 1)), cooked, stock, dry
	end
	-- write the replay back: stock down, bank up, the clock restarted
	local function settle(t, s)
		local coins, cooked, stock = tyDue(t, s)
		t.stock = stock
		t.bank += coins
		t.sales += cooked
		t.since = os.time()
		return coins
	end
	local function tyOpen(t)
		if not t.pieces.counter then return false end
		for _, m in Config.TycoonMenuFor(t.pieces) do
			if canCook(t.stock, m) then return true end
		end
		return false
	end
	-- what every client sees of lot i
	local function tyPublish(i)
		local cfg = tyCfg[i]
		local player = tyOwner[i]
		if not cfg then return end
		if not player then
			cfg:SetAttribute("Owner", 0)
			cfg:SetAttribute("OwnerName", "")
			cfg:SetAttribute("Name", "")
			cfg:SetAttribute("Pieces", "")
			cfg:SetAttribute("Stars", 1)
			cfg:SetAttribute("Open", false)
			cfg:SetAttribute("Chains", 0)
			cfg:SetAttribute("Gold", false)
			return
		end
		local s = sessions[player]
		if not s then return end
		local t = tycoon(saved(s))
		local ids = {}
		for _, p in TY.Pieces do
			if t.pieces[p.id] then table.insert(ids, p.id) end
		end
		cfg:SetAttribute("Owner", player.UserId)
		cfg:SetAttribute("OwnerName", player.DisplayName)
		cfg:SetAttribute("Name", t.name or (player.DisplayName .. "'s"))
		cfg:SetAttribute("Pieces", table.concat(ids, ","))
		cfg:SetAttribute("Stars", Config.TycoonStars(t.xp))
		cfg:SetAttribute("Open", tyOpen(t))
		cfg:SetAttribute("Chains", t.chains)
		cfg:SetAttribute("Gold", (s.passes and s.passes.restaurateur) == true)
	end
	local function tyRelease(player)
		local i = tyLotOf[player]
		if not i then return end
		tyLotOf[player] = nil
		tyOwner[i] = nil
		tyPublish(i)
	end
	Players.PlayerRemoving:Connect(tyRelease)
	-- the summary the owner's cards draw from
	-- has the SHIFT run its course (minutes, like bizDue's)?
	local function tyShiftFull(t)
		return (os.time() - t.shift) / 60 >= (CC.ShiftMinutes or 20)
	end
	local function tySummary(t, s)
		local coins, cooked, _, dry = tyDue(t, s)
		local full = tyShiftFull(t)
		return {
			due = coins, dueOrders = cooked, dry = dry, full = full,
			bank = t.bank, till = t.till, rate = tyRate(t), stars = Config.TycoonStars(t.xp),
			stock = tyStockCount(t.stock), cap = tyStockCap(t, s), open = tyOpen(t),
			chainPrice = TY.Chain.base + TY.Chain.step * t.chains, maxChains = tyMaxChains(s),
			shiftLeft = math.max(0, (CC.ShiftMinutes or 20) * 60 - (os.time() - t.shift)),
		}
	end
	-- fill the stockroom to `cap`, evenly over the ingredients the book uses,
	-- buying crates at the supplier's price; stops when the coins run out.
	-- Returns crates bought and coins spent. `free` = no charge (a product).
	local function tyFill(player, s, t, only, free)
		local cap = tyStockCap(t, s)
		local ids = {}
		for _, m in Config.TycoonMenuFor(t.pieces) do
			for _, gid in m.needs do
				if not table.find(ids, gid) and (not only or only == gid) then table.insert(ids, gid) end
			end
		end
		if #ids == 0 then return 0, 0 end
		local bought, spent, k = 0, 0, 0
		-- two passes: every shelf up to its even share first, then whatever
		-- room the crates' rounding left, round-robin, until the cap
		for _, target in { math.floor(cap / #ids), cap } do
			local progress = true
			while progress do
				progress = false
				for _ = 1, #ids do
					k = k % #ids + 1
					local gid = ids[k]
					local g = Config.Grocery(gid)
					local have = t.stock[gid] or 0
					if have + TY.Crate <= target and tyStockCount(t.stock) + TY.Crate <= cap then
						local price = math.floor(g.price * TY.Crate * TY.CrateDiscount + 0.5)
						-- NOT spend(): that writes the save on every call, and a
						-- FILL IT UP is thirty crates -- thirty queued DataStore
						-- writes (seen in the first test). The caller saves once.
						if free or s.data.Coins >= price then
							if not free then s.data.Coins -= price end
							t.stock[gid] = have + TY.Crate
							bought += 1
							spent += free and 0 or price
							progress = true
							if only then return bought, spent end
						else
							return bought, spent
						end
					end
				end
			end
		end
		return bought, spent
	end
	local function tyName(player, raw)
		raw = string.sub(tostring(raw), 1, 24):gsub("^%s+", ""):gsub("%s+$", "")
		if #raw < 3 then return nil end
		local ok, res = pcall(function()
			local TextService = game:GetService("TextService")
			local r = TextService:FilterStringAsync(raw, player.UserId)
			return r:GetNonChatStringForBroadcastAsync()
		end)
		if ok and type(res) == "string" and #res >= 3 then return res end
		if RunService:IsStudio() then return raw end
		return nil
	end

	-- the Robux products, from ProcessReceipt (forward-declared up there)
	tycoonProduct = function(player, s, prod)
		local c = saved(s)
		local t = tycoon(c)
		if prod.kind == "tycoonRush" then
			settle(t, s)
			t.rushUntil = math.max(os.time(), t.rushUntil) + (prod.minutes or 15) * 60
			feed(player.DisplayName .. "'s restaurant is having a RUSH HOUR!", "rare")
		elseif prod.kind == "tycoonPantry" then
			settle(t, s)
			if not t.pieces.counter then return false end
			tyFill(player, s, t, nil, true)
		elseif prod.kind == "tycoonChain" then
			if t.chains >= tyMaxChains(s) then return false end
			settle(t, s)
			t.chains += 1
			feed(player.DisplayName .. " opened restaurant location #" .. (t.chains + 1), "rare")
		else
			return false
		end
		local i = tyLotOf[player]
		if i then tyPublish(i) end
		return true
	end

	rf("Tycoon").OnServerInvoke = function(player, action, arg)
		local s = session(player)
		-- `state` is polled by the owner's client every few seconds while they
		-- are on their lot; it has its own limiter so a poll landing inside
		-- 0.12s of a BUY never swallows the buy (it did, in the first test)
		if not s or not allow(s, action == "state" and "TycoonState" or "Tycoon", 0.12) then return { ok = false } end
		local c = saved(s)
		local t = tycoon(c)
		local mine = tyLotOf[player]
		local function done(extra)
			local r = { ok = true, lot = mine, sum = tySummary(t, s), data = publicData(s) }
			for k, v in pairs(extra or {}) do r[k] = v end
			return r
		end
		if action == "state" then return done() end
		-- STUDIO ONLY: move the clocks and the stars, so the lazy accrual, the
		-- shift bonus and the chain gate can be tested without waiting an hour.
		-- Same pattern as EventsDev; a live server never sees this branch.
		if action == "dev" and RunService:IsStudio() then
			local a = type(arg) == "table" and arg or {}
			t.since -= tonumber(a.since) or 0
			t.shift -= tonumber(a.shift) or 0
			t.xp += tonumber(a.xp) or 0
			if mine then tyPublish(mine) end
			return done()
		end

		local pos = cityPos(player)
		if not pos then return { ok = false, reason = "you're not in the city" } end
		local lot = mine and tyLots[mine]
		local function atMine(spot, r)
			return lot ~= nil and near(pos, Places.tycoonSpot(lot, spot), r or (TY.SpotRadius + 4))
		end

		if action == "claim" then
			local i = tonumber(arg)
			local L = i and tyLots[i]
			if not L then return { ok = false } end
			if mine then return { ok = false, reason = mine == i and "this is already your lot" or ("you already run lot " .. mine) } end
			if tyOwner[i] then return { ok = false, reason = "somebody already runs this one" } end
			if not near(pos, Places.tycoonSpot(L, "gate"), TY.ClaimRadius + 6) then return { ok = false, reason = "walk up to the gate" } end
			tyOwner[i], tyLotOf[player] = player, i
			mine, lot = i, L
			t.lot = i
			tyPublish(i)
			if not t.pieces.doors then
				feed(player.DisplayName .. " is opening a restaurant on Restaurant Row", "info")
			end
			task.spawn(save, player)
			return done()

		elseif action == "buy" then
			local p = Config.TycoonPiece(tostring(arg))
			if not p then return { ok = false } end
			if not lot then return { ok = false, reason = "claim a lot on Restaurant Row first" } end
			if t.pieces[p.id] then return { ok = false, reason = "you already have that" } end
			if p.needs and not t.pieces[p.needs] then
				return { ok = false, reason = "you need " .. string.lower(Config.TycoonPiece(p.needs).name) .. " first" }
			end
			local onPad = false
			for _, sp in TY.Spots.pads do
				if near(pos, Places.tycoonPoint(lot, sp[1], sp[2]), TY.SpotRadius + 3) then onPad = true break end
			end
			if not onPad then return { ok = false, reason = "stand on the pad" } end
			settle(t, s)
			if not spend(player, s, p.price) then return { ok = false, reason = "not enough coins" } end
			t.pieces[p.id] = true
			tyPublish(mine)
			if p.price >= 2000 then feed(player.DisplayName .. " added " .. string.lower(p.name) .. " to their restaurant", "info") end
			return done({ bought = p.id })

		elseif action == "restock" then
			-- arg = a grocery id for one crate, or "all" to fill the stockroom
			if not lot then return { ok = false, reason = "claim a lot first" } end
			if not atMine("stock") then return { ok = false, reason = "the supplier delivers to the stockroom" } end
			if not t.pieces.counter then return { ok = false, reason = "build the counter first" } end
			settle(t, s)
			local only = arg ~= "all" and tostring(arg) or nil
			if only and not Config.Grocery(only) then return { ok = false } end
			local bought, spent = tyFill(player, s, t, only)
			if bought == 0 then
				if tyStockCount(t.stock) + TY.Crate > tyStockCap(t, s) then return { ok = false, reason = "the stockroom is full" } end
				if only then
					local ids = {}
					for _, m in Config.TycoonMenuFor(t.pieces) do
						for _, gid in m.needs do if not table.find(ids, gid) then table.insert(ids, gid) end end
					end
					if not table.find(ids, only) then return { ok = false, reason = "nothing on your menu uses that" } end
				end
				return { ok = false, reason = "not enough coins for a crate" }
			end
			tyPublish(mine)
			task.spawn(save, player)
			return done({ crates = bought, paid = spent })

		elseif action == "unload" then
			-- your own fridge into the stockroom: already paid for at the market
			if not lot then return { ok = false, reason = "claim a lot first" } end
			if not atMine("stock") then return { ok = false, reason = "unload at the stockroom" } end
			if not t.pieces.counter then return { ok = false, reason = "build the counter first" } end
			settle(t, s)
			local cap = tyStockCap(t, s)
			local moved = 0
			for gid, q in pairs(c.pantry) do
				local room = cap - tyStockCount(t.stock)
				if room <= 0 then break end
				local n = math.min(q, room)
				t.stock[gid] = (t.stock[gid] or 0) + n
				c.pantry[gid] = q - n
				if c.pantry[gid] <= 0 then c.pantry[gid] = nil end
				moved += n
			end
			if moved == 0 then
				return { ok = false, reason = tyStockCount(t.stock) >= cap and "the stockroom is full" or "your fridge is empty" }
			end
			tyPublish(mine)
			task.spawn(save, player)
			return done({ moved = moved, city = public(s) })

		elseif action == "collect" then
			if not lot then return { ok = false, reason = "claim a lot first" } end
			if not atMine("till") then return { ok = false, reason = "collect at the register" } end
			settle(t, s)
			local full = tyShiftFull(t)
			local bonus = full and math.floor(t.bank * (CC.ShiftBonus or 0)) or 0
			local total = t.bank + t.till + bonus
			if total < 1 then
				return { ok = false, reason = tyOpen(t) and "nothing in the till yet" or "the stockroom is bare -- nothing sold" }
			end
			local got = pay(player, s, total, math.floor(t.bank / 20), "BizCollects")
			t.bank, t.till = 0, 0
			t.shift = os.time()
			return done({ coins = got, bonus = bonus, full = full })

		elseif action == "serve" then
			-- arg = { dish = <menu id>, score = 0..1 }. You, at your own pass.
			if type(arg) ~= "table" then return { ok = false } end
			if not lot then return { ok = false, reason = "claim a lot first" } end
			if not atMine("queue") then return { ok = false, reason = "serve from behind the counter" } end
			local m = Config.TycoonDish(tostring(arg.dish))
			if not m or not t.pieces[m.unlock] then return { ok = false, reason = "not on your menu" } end
			settle(t, s)
			if not canCook(t.stock, m) then return { ok = false, reason = "out of ingredients -- restock" } end
			-- THE CLOCK IS OURS: two panel steps take longer than this
			local now = os.clock()
			if s.tyLastServe and now - s.tyLastServe < TY.ServeGap then return { ok = false, reason = "slow down" } end
			s.tyLastServe = now
			consume(t.stock, m)
			local score = math.clamp(tonumber(arg.score) or 0, 0, 1)
			local amount = math.max(1, math.floor(m.price * (TY.ServePay[1] + TY.ServePay[2] * score)))
			local got = pay(player, s, amount, TY.ServeXP, "TycoonServes")
			t.served += 1
			t.xp += TY.StarXP.serve
			tyPublish(mine)
			return done({ coins = got, score = math.floor(score * 100), dish = m.id })

		elseif action == "order" or action == "tip" then
			-- a FRIEND at somebody else's counter. arg = { lot = i, dish = id }
			-- for an order; the tip jar takes the lot alone.
			local a = type(arg) == "table" and arg or { lot = tonumber(arg) }
			local i = tonumber(a.lot)
			local L = i and tyLots[i]
			local owner = L and tyOwner[i]
			if not L then return { ok = false } end
			if not owner then return { ok = false, reason = "nobody is running this restaurant right now" } end
			-- your own kitchen is SERVE, not ORDER -- except in Studio, where
			-- one player has to be able to test both ends of the counter
			if owner == player and not RunService:IsStudio() then return { ok = false, reason = "that's your own kitchen -- serve instead" } end
			if not near(pos, Places.tycoonSpot(L, action == "tip" and "tips" or "queue"), TY.SpotRadius + 4) then
				return { ok = false, reason = "order at the counter" }
			end
			local os_ = sessions[owner]
			if not os_ then return { ok = false } end
			local ot = tycoon(saved(os_))
			local price, m
			if action == "order" then
				m = Config.TycoonDish(tostring(a.dish))
				if not m or not ot.pieces[m.unlock] then return { ok = false, reason = "not on the menu here" } end
				settle(ot, os_)
				if not canCook(ot.stock, m) then return { ok = false, reason = "sold out -- they need to restock" } end
				price = m.price
			else
				price = TY.Tip
			end
			if not spend(player, s, price) then return { ok = false, reason = "not enough coins" } end
			if m then consume(ot.stock, m) end
			ot.till += price
			if m then
				ot.sold += 1
				ot.xp += TY.StarXP.order
				pay(player, s, 0, math.floor(price * TY.DineXPPerCoin), "Dined")
			end
			bump(s.data, action == "order" and "dined" or "tipped", 1)
			task.spawn(save, owner)
			tyPublish(i)
			tyEvent:FireClient(owner, { kind = action, who = player.DisplayName, dish = m and m.name or nil, coins = price })
			mapPassEvent:FireClient(owner, publicData(os_))
			return done({ paid = price, dish = m and m.id or nil, at = i })

		elseif action == "chain" then
			if not lot then return { ok = false, reason = "claim a lot first" } end
			if not near(pos, lot.pos, TY.Reach) then return { ok = false, reason = "sign for it at your restaurant" } end
			if t.chains >= tyMaxChains(s) then return { ok = false, reason = "that is every location you can run" } end
			local pieces = 0
			for _ in pairs(t.pieces) do pieces += 1 end
			if Config.TycoonStars(t.xp) < TY.Chain.minStars then return { ok = false, reason = TY.Chain.minStars .. " stars first -- serve, and get friends in" } end
			if pieces < TY.Chain.minPieces then return { ok = false, reason = "build " .. TY.Chain.minPieces .. " pieces first" } end
			settle(t, s)
			local price = TY.Chain.base + TY.Chain.step * t.chains
			if not spend(player, s, price) then return { ok = false, reason = "not enough coins" } end
			t.chains += 1
			tyPublish(mine)
			feed(player.DisplayName .. " opened restaurant location #" .. (t.chains + 1) .. "!", "rare")
			return done({ chains = t.chains })

		elseif action == "rename" then
			if not lot then return { ok = false, reason = "claim a lot first" } end
			local name = tyName(player, arg)
			if not name then return { ok = false, reason = "3 to 24 letters, and keep it nice" } end
			t.name = name
			tyPublish(mine)
			task.spawn(save, player)
			return done()

		elseif action == "unclaim" then
			tyRelease(player)
			mine, lot = nil, nil
			return done()
		end
		return { ok = false }
	end
	-- AUTO-COLLECT's restaurant leg: the finished shift, banked and paid,
	-- the same minute the shops are. Called from the loop below.
	local function tyAutoCollect(player, s)
		local c = saved(s)
		if type(c.tycoon) ~= "table" then return 0 end
		local t = tycoon(c)
		if not tyShiftFull(t) then return 0 end
		settle(t, s)
		local total = t.bank + t.till
		if total < 1 then return 0 end
		local bonus = math.floor(t.bank * (CC.ShiftBonus or 0))
		local got = pay(player, s, total + bonus, math.floor(t.bank / 20), "BizCollects")
		t.bank, t.till = 0, 0
		t.shift = os.time()
		return got
	end

	---------------------------------------------------------------------------
	-- AUTO-COLLECT (the pass). Every minute, cash out any shop whose SHIFT has
	-- finished -- and only those, never a half-run shift. That is the whole
	-- value of the pass: it is not "you can stop tapping", it is "you never
	-- miss the completion bonus again", including while you are asleep.
	---------------------------------------------------------------------------
	task.spawn(function()
		while true do
			task.wait(60)
			for player, s in sessions do
				if s.passes and s.passes.auto and s.data and s.data.City then
					local c = saved(s)
					local total, bonusTotal, shops = 0, 0, 0
					for _, b in CC.Businesses do
						if c.biz[b.id] then
							local amount, bonus, full = bizDue(c, b, s)
							if full and amount >= 1 then
								c.biz[b.id] = os.time()
								total += amount
								bonusTotal += bonus
								shops += 1
							end
						end
					end
					-- the restaurant is one more shop on the same receipt
					local rest = tyAutoCollect(player, s)
					if rest > 0 then shops += 1 end
					if shops > 0 then
						local got = (total + bonusTotal) > 0 and pay(player, s, total + bonusTotal, math.floor(total / 20), "BizCollects") or 0
						mapPassEvent:FireClient(player, publicData(s))
						autoEvent:FireClient(player, got + rest, shops)
					end
				end
			end
		end
	end)
	---------------------------------------------------------------------------
	-- THE JOB SERVICE. Clocking in and out, paying for work done, and the one
	-- reputation number that follows you between jobs.
	--
	-- WHAT THE SERVER ACTUALLY OWNS, and what it cannot:
	--
	-- The minigame runs on the client -- it has to, it is sixty frames a second
	-- of dragging and tapping -- so the client is the one that reports how well
	-- an order went. That is not a reason to trust it with anything else, and it
	-- is not trusted with anything else:
	--
	--   * PRICE comes from the server's own Config lookup, never from the
	--     payload. The client names WHICH pizza; the server decides what it is
	--     worth.
	--   * SCORE is clamped to 0..1 and then capped by the clock. An order that
	--     arrives faster than half par cannot claim a good score, because it
	--     cannot have been cooked. Fast AND perfect is the one combination
	--     physically unavailable to a script.
	--   * PAY, ELO, streaks and the shift record are all computed here from
	--     Config.JobPay / Config.JobEloDelta. The client is told the result.
	--
	-- So the worst a modified client can do is claim mediocre orders at the real
	-- rate of one every twenty-odd seconds -- which is slower than simply
	-- playing the game well, and that is the bar worth clearing.
	---------------------------------------------------------------------------
	do
		local function jobs(s)
			local d = s.data
			if type(d.Jobs) ~= "table" then d.Jobs = {} end
			local j = d.Jobs
			j.Elo = tonumber(j.Elo) or Config.JobEloStart
			j.Tasks = tonumber(j.Tasks) or 0
			j.Earned = tonumber(j.Earned) or 0
			j.Streak = tonumber(j.Streak) or 0
			if type(j.Done) ~= "table" then j.Done = {} end
			if type(j.Best) ~= "table" then j.Best = {} end
			return j
		end

		local function publicJobs(player, s)
			local j = jobs(s)
			local sh = s.shift
			return {
				elo = math.floor(j.Elo), rank = Config.JobRank(j.Elo), tasks = j.Tasks, earned = j.Earned,
				streak = j.Streak, done = j.Done, best = j.Best,
				job = sh and sh.job or nil,
				title = sh and Config.JobTitle(Config.Job(sh.job), j.Elo) or nil,
				shift = sh and {
					job = sh.job, since = sh.t0, tasks = sh.tasks, earned = sh.earned,
					score = sh.tasks > 0 and math.floor(sh.total / sh.tasks * 100) or 0,
				} or nil,
			}
		end

		-- the uniform is part of the job: everyone can see what you do for a living
		local UNIFORM = { pizzeria = "chefhat", taxi = "shades", delivery = "backpack",
			cleaner = "beanie", farmhand = "sunhat" }
		local function dress(player, s, jobId)
			local u = jobId and UNIFORM[jobId] or nil
			player:SetAttribute("JobUniform", u)
			player:SetAttribute("JobId", jobId)
		end

		rf("Job").OnServerInvoke = function(player, action, arg)
			local s = session(player)
			if not s or not allow(s, "Job", 0.2) then return { ok = false } end
			local j = jobs(s)

			if action == "state" then
				return { ok = true, jobs = publicJobs(player, s) }

			elseif action == "start" then
				local def = Config.Job(tostring(arg))
				if not def then return { ok = false } end
				if def.soon then return { ok = false, reason = "that one is not open yet" } end
				if j.Elo < (def.elo or 0) then
					return { ok = false, reason = "you need " .. def.elo .. " reputation for that" }
				end
				s.shift = { job = def.id, t0 = os.time(), tasks = 0, earned = 0, total = 0, last = 0 }
				dress(player, s, def.id)
				return { ok = true, jobs = publicJobs(player, s), data = publicData(s) }

			elseif action == "quit" then
				local sh = s.shift
				s.shift = nil
				dress(player, s, nil)
				-- clocking out is free; ABANDONING a task in progress is the small
				-- penalty, and it is small on purpose
				if arg == "abandon" and sh and sh.tasks == 0 then
					j.Elo = math.max(0, j.Elo - 2)
				end
				j.Streak = 0
				task.spawn(save, player)
				return { ok = true, summary = sh and {
					job = sh.job, tasks = sh.tasks, earned = sh.earned,
					mins = math.floor((os.time() - sh.t0) / 60),
					score = sh.tasks > 0 and math.floor(sh.total / sh.tasks * 100) or 0,
				} or nil, jobs = publicJobs(player, s), data = publicData(s) }

			elseif action == "task" then
				-- arg = { item = <menu id>, score = 0..1, secs = <how long it took> }
				local sh = s.shift
				if not sh then return { ok = false, reason = "clock in first" } end
				if type(arg) ~= "table" then return { ok = false } end
				local def = Config.Job(sh.job)
				if not def then return { ok = false } end

				-- THE PRICE IS OURS, not the client's -- and an item that is not
				-- on our menu is not a typo to forgive, it is a payload we did
				-- not write, so it is refused rather than quietly priced.
				local base, par = def.base or 50, 40
				local R = def.room and Config.Restaurant(def.room)
				if R then
					par = R.par or 40
					base = nil
					for _, m in R.menu do
						if m.id == tostring(arg.item) then base = m.pay break end
					end
					if not base then return { ok = false, reason = "not on the menu" } end
				end

				-- THE CLOCK IS OURS TOO, and it does two separate jobs here.
				--
				-- First, credibility: an order that arrives faster than half par
				-- cannot have been cooked, so the score it claims is capped by
				-- how long it actually took.
				--
				-- Second, and more important, PACE. The per-order rate is
				-- balanced against an order taking about `par`. Without this a
				-- script claiming one every 21 seconds would earn at twice the
				-- intended rate while playing none of the game. So the payout
				-- scales with the time the order really took, which leaves an
				-- honest fast cook slightly ahead on coins per minute and a
				-- rusher slightly behind -- exactly the right way round.
				local now = os.time()
				local gap = now - (sh.last > 0 and sh.last or sh.t0)
				if gap < math.floor(par * 0.5) then return { ok = false, reason = "slow down" } end
				local score = math.clamp(tonumber(arg.score) or 0, 0, 1)
				score = math.min(score, math.clamp(gap / (par * 0.85), 0, 1))
				local paced = math.clamp(0.35 + gap / par * 0.65, 0, 1)

				local amount, b, perf, tip, mult = Config.JobPay(base, score, j.Elo)
				amount = math.max(1, math.floor(amount * paced))
				sh.last = now
				sh.tasks += 1
				sh.total += score
				j.Tasks += 1
				j.Streak += 1
				j.Done[sh.job] = (j.Done[sh.job] or 0) + 1
				local pct = math.floor(score * 100)
				if (j.Best[sh.job] or 0) < pct then j.Best[sh.job] = pct end

				local streakBonus = Config.JobStreakBonus(j.Streak)
				local before = j.Elo
				j.Elo = math.clamp(j.Elo + Config.JobEloDelta(score), 0, 5000)

				-- through pay() like every other city job, so CITY PRO, VIP, the
				-- 2x pass and any live boost all apply exactly as they do elsewhere
				local got = pay(player, s, amount + streakBonus, math.max(1, math.floor(amount / 12)), "JobTasks")
				sh.earned += got
				j.Earned += got
				if j.Tasks % 5 == 0 then task.spawn(save, player) end
				if streakBonus > 0 and j.Streak >= 10 then
					feed(player.DisplayName .. " is on a " .. j.Streak .. "-job streak!", "rare")
				end
				return { ok = true, coins = got, base = b, perf = perf, tip = tip, mult = mult,
					streak = j.Streak, streakBonus = streakBonus, score = pct,
					elo = j.Elo, eloDelta = j.Elo - before, rank = Config.JobRank(j.Elo),
					jobs = publicJobs(player, s), data = publicData(s) }

			elseif action == "resetElo" then
				local cost = Config.JobEloResetCost
				if j.Elo == Config.JobEloStart then return { ok = false, reason = "nothing to reset" } end
				if not spend(player, s, cost) then return { ok = false, reason = "not enough coins" } end
				j.Elo = Config.JobEloStart
				j.Streak = 0
				task.spawn(save, player)
				return { ok = true, jobs = publicJobs(player, s), data = publicData(s) }
			end
			return { ok = false }
		end

		-- A world-job task has just paid out through its own loop. Record it
		-- against the shift and the reputation -- but do NOT pay again:
		-- `got` is the coins that loop already handed over.
		creditWorld = function(player, s, jobId, quality, got)
			local sh = s.shift
			if not sh or sh.job ~= jobId then return end
			local jj = jobs(s)
			local q = math.clamp(quality or 1, 0, 1)
			local w = math.clamp((Config.Job(jobId) or {}).weight or 1, 0.02, 1)
			sh.earned += (got or 0)
			sh.last = os.time()
			jj.Earned += (got or 0)
			-- fractional work banks up; the counters only move on a whole task
			sh.frac = (sh.frac or 0) + w
			jj.Elo = math.clamp(jj.Elo + Config.JobEloDelta(q) * w, 0, 5000)
			local bonus = 0
			if sh.frac < 1 then
				jobEvent:FireClient(player, publicJobs(player, s), got, 0)
				return
			end
			sh.frac -= 1
			sh.tasks += 1
			sh.total += q
			jj.Tasks += 1
			jj.Streak += 1
			jj.Done[jobId] = (jj.Done[jobId] or 0) + 1
			bonus = Config.JobStreakBonus(jj.Streak)
			if bonus > 0 then
				local extra = pay(player, s, bonus, 2, "JobTasks")
				sh.earned += extra
				jj.Earned += extra
			end
			jobEvent:FireClient(player, publicJobs(player, s), got, bonus)
		end

		-- clocking out is implicit if you leave; the shift lives on the session,
		-- not in the save, so nothing has to be cleaned up on rejoin
		Players.PlayerRemoving:Connect(function(player)
			local s = sessions[player]
			if s then s.shift = nil end
		end)
	end

	---------------------------------------------------------------------------
	-- CITY EVENTS: the director. See docs/LOOPS.md and Config.Events.
	--
	-- One loop per server, and it is the only thing that starts an event.
	--
	-- THE SPOT IS A SECRET THE SERVER KEEPS. For a hidden event the public
	-- record carries clues and nothing else; the exact position goes only to
	-- players who are already within RevealRadius of it, one FireClient each.
	-- So the client draws the thing when you are close enough to see it, and a
	-- script reading the remotes from across town learns nothing to teleport
	-- to. Every claim is then checked against where the character really is,
	-- and paid through pay() so boosts and passes apply like any other income.
	--
	-- All clocks are workspace:GetServerTimeNow(), which every client shares
	-- (the weather and the traffic lights already run off it), so a countdown
	-- needs no syncing.
	---------------------------------------------------------------------------
	do
		local EV = Config.Events
		local evRemote = Instance.new("RemoteEvent")
		evRemote.Name = "CityEvent"
		evRemote.Parent = remotes

		local live = {}        -- uid -> event
		local gone = {}        -- uid -> true, for collect events that have ended
		local uidSeq = 0
		local lastHeadline = {} -- ids of the last few headlines, so they do not repeat
		local function now() return workspace:GetServerTimeNow() end
		local function between(r) return r[1] + math.random() * (r[2] - r[1]) end

		-- THE DAILY 3's FORWARD SLOTS (phase D). The hunt is a self-contained
		-- block at the bottom of this `do` block -- it shares streetLots, the
		-- door geometry, compass/nearestLandmark/streetOf/areaOf, cityPos, pay
		-- and evRemote, and shares no lifecycle with the director. A `local
		-- function` is invisible to every line above it, so the five places
		-- that have to reach forwards into it declare their slots here and the
		-- hunt fills them in. Every caller tests for nil first, so the city
		-- still runs in full if the hunt ever fails to initialise.
		local huntLotTaken -- (lot) -> true if it is one of today's three
		local huntNear     -- (x, z, r2) -> true if within sqrt(r2) of a spot
		local huntTick     -- called once a second by the shared reveal loop
		local huntPublic   -- (player, s, fresh) -> the `hunt` block on a state reply
		local huntClaimFn  -- (player, s, i) -> the huntClaim reply
		local huntDev      -- (player, cmd, arg) -> the Studio-only hooks

		local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
		local function compass(from, to)
			-- NORTH IS +Z. The city map draws +Z at the top and the game's own
			-- copy says the farm fields (z = +450) are "up north"; a clue has
			-- to agree with the map the player is holding.
			local d = to - from
			local a = math.atan2(d.X, d.Z)
			return COMPASS[math.floor((a / (math.pi * 2) * 8 + 8.5)) % 8 + 1]
		end
		local function nearestLandmark(pos)
			local best, bd
			for _, l in Places.CityLandmarks do
				local d = (l.pos - pos).Magnitude
				if not bd or d < bd then best, bd = l, d end
			end
			return best, bd
		end
		local function streetOf(lot)
			return (string.gsub(lot.address or "Main St", "^%d+%s+", ""))
		end
		local function areaOf(lot, pos)
			if lot.district then return "the " .. lot.district .. " district" end
			return "the " .. compass(Vector3.zero, pos) .. " of town"
		end

		-- A spot on the pavement beside a front door: open ground by
		-- construction (every lot's door is on the kerb), close to a facade so
		-- it reads as tucked away, and never inside a building.
		--
		-- THE DEPTH WAS MEASURED. The first version stood things 1.5 studs
		-- BEHIND the door point, to tuck them against the wall -- and seven of
		-- eight sampled spots came back embedded in a shop window, because
		-- the facade plane is exactly there. 2.5 in FRONT of the door point
		-- puts a Sminski-sized thing clear of the glass with its back to it.
		--
		-- THE TRUCK PARKS IN THE GUTTER, ALSO MEASURED. Out from the door
		-- line: pavement to +12 (with a row of posts at +8, which the first
		-- version parked on top of at every single door), kerb at +12, and the
		-- traffic lane's near edge at +18.9. The truck is 6.3 wide, so centred
		-- at +15.3 it sits between kerb and traffic like a real one.
		--
		-- Both numbers only mean anything on a lot with the standard street
		-- section -- door 118 out from a block centre -- so only those are
		-- used. The server cannot check geometry (the world is built on the
		-- client), which is exactly why the spots have to be right by
		-- construction rather than tested at runtime.
		local streetLots = {}
		for _, lot in lots do
			if lot.door and lot.face then
				local n = Vector3.new(math.sin(lot.face), 0, math.cos(lot.face))
				local q = lot.door:Dot(n) - 118 - 150
				local off = q % 300
				if math.min(off, 300 - off) < 1 then table.insert(streetLots, lot) end
			end
		end
		-- WHERE A COLLECT EVENT CAN BE CENTRED, WORKED OUT ONCE AT STARTUP.
		--
		-- A collect event scatters up to 48 items on the eligible lots within
		-- EV.Zone of a centre lot. Most lots have plenty of neighbours (the
		-- median is about 15) but the thinnest has only THREE, which is 12
		-- slots -- not enough for one event, and a "pick a centre, then keep
		-- trying to place" loop would spin there forever looking for room that
		-- does not exist.
		--
		-- So the pool of legal centres is computed here, once: O(n^2) over
		-- ~381 lots at server start, never per event. A lot counts itself, so
		-- MinCentreLots = 12 means 12 x SlotsPerLot = 48 slots are reachable
		-- before any spacing rule throws some away.
		local centreLots = {}
		do
			local zone = EV.Zone or 170
			local z2 = zone * zone
			local need = EV.MinCentreLots or 12
			local nearby, xs, zs = {}, {}, {}
			for i = 1, #streetLots do
				nearby[i] = { streetLots[i] }
				xs[i], zs[i] = streetLots[i].door.X, streetLots[i].door.Z
			end
			for i = 1, #streetLots do
				local ax, az = xs[i], zs[i]
				for k = i + 1, #streetLots do
					local dx, dz = ax - xs[k], az - zs[k]
					if dx * dx + dz * dz <= z2 then
						table.insert(nearby[i], streetLots[k])
						table.insert(nearby[k], streetLots[i])
					end
				end
			end
			for i, lot in streetLots do
				if #nearby[i] >= need then
					table.insert(centreLots, { lot = lot, near = nearby[i] })
				end
			end
			if #centreLots == 0 then
				-- never leave the director with nothing to pick; a thinner
				-- zone only means fewer items, which start() already handles
				for i, lot in streetLots do
					table.insert(centreLots, { lot = lot, near = nearby[i] })
				end
			end
		end

		local function pickSpot(hidden)
			local lot = streetLots[math.random(1, #streetLots)]
			-- NEVER ONE OF THE DAILY 3's LOTS. A hidden find sits at
			-- door + t*(+/-11) + n*2.5, which is the hunt's own formula, so two
			-- claimable things would share a spot. 3 lots in ~381 means the
			-- retry runs under 1% of the time, and it is bounded, so it cannot
			-- spin even if the pool were tiny.
			if huntLotTaken then
				local tries = Config.Hunt.Retries or 6
				while tries > 0 and huntLotTaken(lot) do
					lot = streetLots[math.random(1, #streetLots)]
					tries -= 1
				end
			end
			local n = Vector3.new(math.sin(lot.face), 0, math.cos(lot.face))
			local t = Vector3.new(n.Z, 0, -n.X)
			local side = math.random() < 0.5 and -1 or 1
			local pos = hidden and (lot.door + t * side * 11 + n * 2.5) or (lot.door + n * 15.3)
			return pos, lot, hidden and lot.face or (lot.face + math.pi / 2)
		end

		local function rollSighting()
			local total = 0
			for _, t in EV.Tiers do total += t.weight end
			local r = math.random() * total
			local tier = EV.Tiers[1]
			for _, t in EV.Tiers do
				r -= t.weight
				if r <= 0 then tier = t break end
			end
			local pool = {}
			for _, sk in Config.Skins do
				if sk.id ~= "none" and Config.SightingTier(sk).id == tier.id then table.insert(pool, sk) end
			end
			if #pool == 0 then
				for _, sk in Config.Skins do if sk.id ~= "none" then table.insert(pool, sk) end end
			end
			return pool[math.random(1, #pool)], tier
		end

		-- what everyone may know
		local function publicEv(ev)
			local p = {
				uid = ev.uid, id = ev.def.id, startT = ev.startT, endT = ev.endT,
				clues = ev.clues, area = ev.area, found = ev.found, firstBy = ev.firstBy,
				quiet = ev.quiet, -- an ambient sighting nobody has reported yet
				spot = ev.def.open and { ev.pos.X, ev.pos.Z, ev.face } or nil,
				hint = ev.hint,
			}
			-- A COLLECT ZONE IS NOT A SECRET. Unlike a hidden find, the whole
			-- point is that everyone converges on it, so the item list ships
			-- in the public record -- minus the ones already taken, so a
			-- player who joins mid-event draws exactly what is still there.
			-- `spot` is the zone centre in the existing shape, so the map
			-- marker and the phone's GO button need no new code.
			if ev.items then
				local list = {}
				for _, it in ev.items do
					if not ev.taken[it.id] then
						table.insert(list, { id = it.id, x = it.pos.X, z = it.pos.Z })
					end
				end
				p.items = list
				p.got = ev.got
				p.goal = ev.goal   -- cooperative only
				p.left = ev.left   -- competitive only
				p.top = ev.top     -- competitive only
			end
			return p
		end
		-- what only someone standing near it may know.
		--
		-- `spot` HERE IS POSITIONAL -- { X, Z, face } -- and that is correct:
		-- phase A's client unpacks it positionally. The Daily 3's huntReveal
		-- uses the KEY form { x =, z =, face = } because its client reads keys.
		-- Two shapes for two consumers, deliberately. Unifying them breaks one
		-- of the two silently, with no error and nothing drawn.
		local function secret(ev)
			return { uid = ev.uid, spot = { ev.pos.X, ev.pos.Z, ev.face }, skin = ev.skin and ev.skin.id, tier = ev.tier and ev.tier.id }
		end

		local function cityCount()
			local n = 0
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Activity") == "city" then n += 1 end
			end
			return n
		end

		-- THE SLOT GRID, AND WHY IT IS A GRID AND NOT A RANDOM SCATTER.
		--
		-- The server cannot see the world, so every item has to be provably
		-- clear rather than tested. Four slots per lot, on the +2 strip out
		-- from the door line (the one that measured 0/105 blocked with open
		-- sky), at -12 / -4 / +4 / +12 along the frontage: inside a lot they
		-- are 8 apart, and adjacent doors are 32 apart along a street, so one
		-- lot's +12 and the next lot's -12 are also exactly 8 apart. Nothing
		-- lands on the posts at +8, the lamps at +10, the kerb at +12 or --
		-- the expensive mistake phase A already made -- inside a shop window
		-- at -1.5.
		local SLOT_ALONG = { -12, -4, 4, 12 }
		local function scatter(centre, want, origin)
			local slots = {}
			local perLot = math.clamp(EV.SlotsPerLot or 4, 1, #SLOT_ALONG)
			local zone2 = (EV.Zone or 170) ^ 2
			for _, lot in centre.near do
				local n = Vector3.new(math.sin(lot.face), 0, math.cos(lot.face))
				local t = Vector3.new(n.Z, 0, -n.X)
				local base = lot.door + n * 2
				for i = 1, perLot do
					local p = base + t * SLOT_ALONG[i]
					-- the lots are chosen door-to-door, but a slot sits up to
					-- 12 along the frontage from its door, so a few of them
					-- fall outside the zone the HUD advertises. Drop those:
					-- every item must be inside the circle players are told
					-- to search, or the count and the zone disagree.
					local dx, dz = p.X - origin.X, p.Z - origin.Z
					if dx * dx + dz * dz <= zone2 then table.insert(slots, p) end
				end
			end
			-- shuffle, so the scatter is not a tidy line down one street
			for i = #slots, 2, -1 do
				local j = math.random(1, i)
				slots[i], slots[j] = slots[j], slots[i]
			end

			local items = {}
			for _, p in slots do
				if #items >= want then break end
				local ok = true
				-- (1) never within 12 studs of a live event's spot. A hidden
				-- find sits at door + t*(+/-11) + n*2.5, which is half a stud
				-- from this grid's +12 slot: two claimable things in one place
				-- is a bug, and it happens without this check.
				for _, other in live do
					local dx, dz = p.X - other.pos.X, p.Z - other.pos.Z
					if dx * dx + dz * dz < 144 then ok = false break end
				end
				-- (1b) and the same 12 studs from one of the Daily 3's spots,
				-- for the same reason and the same arithmetic. The hunt is not
				-- an event, so it is not in `live` and the loop above misses it.
				if ok and huntNear and huntNear(p.X, p.Z, 144) then ok = false end
				-- (2) never within 8 studs of an item already placed. The grid
				-- guarantees this along a straight street; corner lots, whose
				-- two frontages meet at an angle the grid does not reason
				-- about, are why it is checked anyway.
				--
				-- 63.5, NOT 64, AND THE DIFFERENCE MATTERS. Vector3 is
				-- float32: a pair the grid builds exactly 8 apart squares to
				-- 64 give or take a few thousandths once it has been through
				-- a sin/cos and a door coordinate of ~900. Testing against 64
				-- would throw away most of the grid and leave one item per
				-- lot. 63.5 is 7.97 studs, which is the same rule in practice.
				if ok then
					for _, it in items do
						local dx, dz = p.X - it.pos.X, p.Z - it.pos.Z
						if dx * dx + dz * dz < 63.5 then ok = false break end
					end
				end
				if ok then
					table.insert(items, { id = #items + 1, pos = p })
				end
			end
			-- If the exclusions ate too many slots we place what fits and the
			-- caller scales the goal down to match. We never wait for a slot.
			return items
		end

		local function start(def, centre)
			uidSeq += 1
			local hidden = not def.open
			local pos, lot, face
			local items
			if def.kind == "collect" then
				centre = centre or centreLots[math.random(1, #centreLots)]
				lot = centre.lot
				face = lot.face
				-- the zone centre stands on the same clear +2 strip the items do
				pos = lot.door + Vector3.new(math.sin(face), 0, math.cos(face)) * 2
				local want
				if def.shared then
					local n = math.max(1, cityCount())
					want = math.clamp((def.base or 12) + (def.per or 0) * (n - 1), def.base or 12, def.maxCount or 48)
				else
					want = def.count or 24
				end
				items = scatter(centre, want, pos)
				if #items == 0 then
					warn("[events] " .. tostring(def.id) .. ": no free slots at the chosen centre")
				end
			else
				pos, lot, face = pickSpot(hidden)
			end
			local t0 = now()
			local ev = {
				uid = uidSeq, def = def, pos = pos, lot = lot, face = face,
				startT = t0 + (def.warn or 0), endT = t0 + (def.warn or 0) + def.lasts,
				claimed = {}, revealed = {}, found = 0, quiet = def.ambient or nil,
			}
			if items then
				-- COLLECT STATE. `taken` is keyed by itemId, not by player:
				-- there is no once-per-player limit here, a player takes as
				-- many as they can reach. `counts` is the per-player tally
				-- that the client shows as YOU n.
				ev.items = items
				ev.byId = {}
				for _, it in items do ev.byId[it.id] = it end
				ev.taken = {}
				ev.counts = {}
				ev.got = 0
				ev.sentGot = 0
				ev.total = #items
				ev.goal = def.shared and #items or nil
				ev.left = (not def.shared) and #items or nil
			end
			ev.area = areaOf(lot, pos)
			if def.id == "sighting" then ev.skin, ev.tier = rollSighting() end
			if def.open then
				local lm = nearestLandmark(pos)
				ev.clues = { { t = t0, text = "on " .. streetOf(lot) .. ", near " .. lm.name } }
			elseif def.clues then
				local lm = nearestLandmark(pos)
				local texts = {
					"somewhere in " .. ev.area,
					"on " .. streetOf(lot),
					compass(lm.pos, pos) .. " of " .. lm.name,
				}
				ev.clues = {}
				for i, dt in def.clues do
					ev.clues[i] = { t = ev.startT + dt, text = texts[i] or texts[#texts] }
				end
			end
			live[ev.uid] = ev
			if not ev.quiet then evRemote:FireAllClients("start", publicEv(ev)) end
			return ev
		end

		local function finish(ev)
			live[ev.uid] = nil
			-- A pickup can be in flight when the event is torn down, and the
			-- refusal a collect client shows is worded differently from a
			-- find's, so remember which uids were collect events. One integer
			-- key per event, a couple of dozen an hour.
			if ev.def.kind == "collect" then gone[ev.uid] = true end
			if not ev.quiet then
				evRemote:FireAllClients("end", { uid = ev.uid, id = ev.def.id, found = ev.found, firstBy = ev.firstBy })
			end
		end

		-- an ambient sighting goes public: either someone found it, or it has
		-- sat unseen long enough that "someone saw something" makes the news
		local function goPublic(ev, why)
			if not ev.quiet then return end
			ev.quiet = nil
			local lm = nearestLandmark(ev.pos)
			ev.clues = {
				{ t = now(), text = "somewhere in " .. ev.area },
				{ t = now() + 20, text = compass(lm.pos, ev.pos) .. " of " .. lm.name },
			}
			evRemote:FireAllClients("start", publicEv(ev), why)
		end

		-----------------------------------------------------------------------
		-- COLLECT: the shared counter.
		--
		-- This is the first number in the city that belongs to the SERVER
		-- rather than to you, so the two numbers must never be confused:
		-- `ev.got` is the city's total and goes to everyone, `ev.counts[uid]`
		-- is yours and only ever comes back to you as `myCount`. (Not `mine`
		-- -- `ev.mine` already means "I claimed this" on the client and
		-- setting it on a collect event deletes the HUD strip.)
		-----------------------------------------------------------------------
		local function progressOf(ev)
			return { uid = ev.uid, got = ev.got, left = ev.left, goal = ev.goal, top = ev.top }
		end

		-- Broadcast at most four times a second per event, and only when the
		-- number actually moved. The leading edge fires immediately, which is
		-- the normal case; a burst gets one trailing send so the last pickup
		-- is never the one nobody hears about.
		local function pushProgress(ev)
			if ev.got == ev.sentGot then return end
			local t = now()
			local since = t - (ev.sentT or 0)
			if since >= 0.25 then
				ev.sentT, ev.sentGot = t, ev.got
				evRemote:FireAllClients("progress", progressOf(ev))
			elseif not ev.pending then
				ev.pending = true
				task.delay(0.25 - since, function()
					ev.pending = false
					if live[ev.uid] ~= ev or ev.got == ev.sentGot then return end
					ev.sentT, ev.sentGot = now(), ev.got
					evRemote:FireAllClients("progress", progressOf(ev))
				end)
			end
		end

		-- The finish moment, then teardown. `done` goes out first so the
		-- clients have something to play, and the event only actually ends
		-- once the grace window below is up. This is also the one place a
		-- collect event's coins reach the DataStore in the normal case.
		local function finishCollect(ev, why)
			if ev.over then return end
			ev.over = why
			ev.sentGot, ev.sentT = ev.got, now()
			-- EVERY ENDING GETS A GRACE WINDOW, INCLUDING THE TIMEOUT. The
			-- client's finish card and its consolation chime both guard on the
			-- event still being in its list, so calling finish() in the same
			-- frame as this broadcast deletes the entry before either can run
			-- -- which is exactly how the timeout ending shipped silent the
			-- first time. The client's measured floor is 1.7s (0.80 for the
			-- notification, up to 0.85 more for the chime after a fanfare), so
			-- a timeout gets 2s: past the floor, and short enough that an
			-- expired countdown does not sit there looking like an overrun.
			-- A goal or a clean sweep keeps 5s, which is a moment worth having.
			local grace = why == "time" and 2 or 5
			ev.tearAt = now() + grace
			evRemote:FireAllClients("done", { uid = ev.uid, why = why, got = ev.got, goal = ev.goal, top = ev.top })
			local def = ev.def
			local payBonus = why == "goal" and (def.bonus or 0) > 0 and def.bonusAt ~= nil
			for _, player in Players:GetPlayers() do
				local mine = ev.counts[player.UserId]
				if mine and mine > 0 then
					local bonus = 0
					local s = sessions[player]
					if s then
						if payBonus and mine >= def.bonusAt then
							bonus = pay(player, s, def.bonus, def.bonusXp or 0, "EventsDone", true)
						end
						-- THE ONE WRITE PER CONTRIBUTOR PER EVENT. Every item
						-- this player collected deferred its save to here --
						-- and if the flush loop already wrote them, flushPay
						-- no-ops rather than spending a second write.
						task.spawn(flushPay, player, s)
					end
					-- the save rides along so the coin pill moves with the
					-- "bonus paid" line rather than on the next state push;
					-- `s` can be nil for a player whose session has gone, and
					-- publicData() would throw on that, so it stays optional
					evRemote:FireClient(player, "reward", { uid = ev.uid, myCount = mine, bonus = bonus,
						data = s and publicData(s) or nil })
				end
			end
			task.delay(grace, function()
				if live[ev.uid] == ev then finish(ev) end
			end)
		end

		-- ONE CLAIM PER ITEM, EVER.
		--
		-- Everything from reading `ev.taken[id]` to writing it happens with no
		-- yield in between, so two claims landing in the same frame cannot
		-- both get past it. The payment follows the write, not the other way
		-- round: if pay() ever started yielding, the item would already be
		-- spoken for. Nothing here trusts the client beyond the item id, and
		-- that is looked up in the event's own table and distance-checked
		-- against where the character really is.
		local function collectClaim(player, s, ev, itemId)
			local def = ev.def
			local id = tonumber(itemId)
			if not id then return { ok = false, reason = "already gone" } end
			local t = now()
			-- during the warn window the items exist but are not yet in play;
			-- refuse silently rather than invent a fourth refusal string
			if t < ev.startT then return { ok = false } end
			if ev.over or t >= ev.endT then return { ok = false, reason = "it's over" } end
			-- a cooperative goal that is already met stops counting
			if ev.goal and ev.got >= ev.goal then return { ok = false, reason = "it's over" } end
			local item = ev.byId[id]
			if not item then return { ok = false, reason = "already gone" } end
			if ev.taken[id] then return { ok = false, reason = "already gone" } end
			local pos = cityPos(player)
			if not pos or (pos - item.pos).Magnitude > (EV.PickupServer or 9) then
				return { ok = false, reason = "too far away" }
			end

			----- no yield from here ------------------------------------------
			ev.taken[id] = player.UserId
			ev.got += 1
			if ev.left then ev.left = math.max(0, ev.total - ev.got) end
			local mine = (ev.counts[player.UserId] or 0) + 1
			ev.counts[player.UserId] = mine
			if not def.shared and mine > ((ev.top and ev.top.n) or 0) then
				ev.top = { name = player.DisplayName, n = mine }
			end
			-- `defer`: one save per item would be 288 DataStore writes for a
			-- 48-item event with six players. The flush loop, the finish
			-- below, leaving the city and leaving the game all write instead.
			local coins = pay(player, s, def.each or 0, def.xp or 0, "EventsDone", true)
			-- a cleaner who is clocked in gets the shift credit too; this
			-- no-ops for everyone else, so it is called unconditionally
			if def.credits and creditWorld then creditWorld(player, s, def.credits, 1, coins) end
			----- to here ----------------------------------------------------

			evRemote:FireAllClients("taken", { uid = ev.uid, itemId = id, by = player.DisplayName })
			pushProgress(ev)
			if ev.goal and ev.got >= ev.goal then
				task.spawn(finishCollect, ev, "goal")
			elseif ev.left == 0 then
				task.spawn(finishCollect, ev, "empty")
			end
			return { ok = true, coins = coins, xp = def.xp or 0, myCount = mine,
				got = ev.got, left = ev.left, goal = ev.goal, top = ev.top,
				id = def.id, data = publicData(s) }
		end

		rf("Events").OnServerInvoke = function(player, action, arg, arg2)
			local s = session(player)
			if not s then return { ok = false } end
			-- A collect pickup is a movement side effect, not a button press:
			-- running through a dense scatter can produce several a second, so
			-- it gets its own 10/s budget instead of brushing against the 4/s
			-- one every other event call shares. Which bucket applies is
			-- decided from the event on the server, never from the arguments.
			local claiming = action == "claim" and live[tonumber(arg) or -1]
			if claiming and claiming.def.kind == "collect" then
				if not allow(s, "EventsPickup", 0.1) then return { ok = false } end
			elseif not allow(s, "Events", 0.25) then
				return { ok = false }
			end
			if action == "state" then
				local list = {}
				for _, ev in live do
					if not ev.quiet then
						local p = publicEv(ev)
						-- per-player, so someone who just walked in gets 0
						if ev.items then p.myCount = ev.counts[player.UserId] or 0 end
						table.insert(list, p)
					end
				end
				local c = saved(s)
				local out = { ok = true, events = list, spotted = type(c.spotted) == "table" and c.spotted or {}, now = now() }
				-- `state` is how a client says "I have just (re)built the city",
				-- so it also clears this player's hunt reveals: the models are
				-- gone with the old world and have to be sent again.
				if huntPublic then out.hunt = huntPublic(player, s, true) end
				return out

			elseif action == "huntClaim" then
				if not huntClaimFn then return { ok = false } end
				return huntClaimFn(player, s, arg)

			elseif action == "claim" then
				local ev = claiming or nil
				if not ev then
					if gone[tonumber(arg) or -1] then return { ok = false, reason = "it's over" } end
					return { ok = false, reason = "too late -- it has gone" }
				end
				if ev.def.kind == "collect" then return collectClaim(player, s, ev, arg2) end
				local t = now()
				if t < ev.startT then return { ok = false, reason = "not yet" } end
				if ev.claimed[player.UserId] then return { ok = false } end
				local pos = cityPos(player)
				if not pos or (pos - ev.pos).Magnitude > EV.ClaimRadius then return { ok = false, reason = "get closer" } end
				ev.claimed[player.UserId] = true
				ev.found += 1
				local def = ev.def
				local coins = (ev.tier and ev.tier.coins) or def.coins or 0
				local firstBonus = 0
				if ev.found <= (def.firstN or 1) then firstBonus = def.first or 0 end
				local got = pay(player, s, coins + firstBonus, def.xp or 0, "EventsDone")
				local out = { ok = true, coins = got, first = firstBonus > 0, id = def.id }
				if ev.skin then
					local c = saved(s)
					if type(c.spotted) ~= "table" then c.spotted = {} end
					out.isNew = c.spotted[ev.skin.id] == nil
					c.spotted[ev.skin.id] = (c.spotted[ev.skin.id] or 0) + 1
					out.skin, out.tier, out.spotted = ev.skin.id, ev.tier.id, c.spotted
					if ev.tier.id == "rare" or ev.tier.id == "legendary" then
						feed(player.DisplayName .. " spotted a " .. ev.tier.name .. " Sminski: " .. ev.skin.name .. "!", "rare")
					end
				end
				if ev.found == 1 then
					ev.firstBy = player.DisplayName
					if ev.quiet then
						goPublic(ev, "found")
					end
					if def.afterFound then ev.endT = math.min(ev.endT, t + def.afterFound) end
					if not def.open then
						-- latecomers get a circle to search, off-centre so the
						-- middle of it is not simply the answer
						local a, r = math.random() * math.pi * 2, math.random() * 45
						ev.hint = { ev.pos.X + math.cos(a) * r, ev.pos.Z + math.sin(a) * r, 80 }
					end
				end
				evRemote:FireAllClients("found", { uid = ev.uid, found = ev.found, firstBy = ev.firstBy, who = player.DisplayName, endT = ev.endT, hint = ev.hint })
				out.data = publicData(s)
				return out
			end
			return { ok = false }
		end

		-- reveal: once a second, tell anyone who has wandered close enough
		task.spawn(function()
			while true do
				task.wait(1)
				local t = now()
				-- THE DAILY 3 RIDES THIS LOOP, not a second task.spawn: one
				-- extra pass over three spots, plus the UTC day check. It is
				-- wrapped because a fault in a day-long side feature must not
				-- be able to stop phase A and B reveals and expiries.
				if huntTick then
					local okTick, err = pcall(huntTick)
					if not okTick then warn("[hunt] " .. tostring(err)) end
				end
				for _, ev in live do
					if ev.over then
						-- a collect event that has already announced how it
						-- ended: hold the entry until its grace window is up,
						-- so this loop cannot tear it down before the client
						-- has drawn the finish. Only collect sets `over`, so
						-- a find never reaches this branch.
						if t >= (ev.tearAt or 0) then finish(ev) end
					elseif t >= ev.endT then
						-- a collect event announces how it ended before it goes
						if ev.def.kind == "collect" then
							finishCollect(ev, "time")
						else
							finish(ev)
						end
					elseif t >= ev.startT and not ev.def.open then
						if ev.quiet and ev.def.newsAfter and t - ev.startT >= ev.def.newsAfter then goPublic(ev, "news") end
						for _, player in Players:GetPlayers() do
							if not ev.revealed[player.UserId] then
								local pos = cityPos(player)
								if pos and (pos - ev.pos).Magnitude <= EV.RevealRadius then
									ev.revealed[player.UserId] = true
									evRemote:FireClient(player, "reveal", secret(ev))
								end
							end
						end
					end
				end
			end
		end)

		-- the schedule: headlines never overlap each other; ambient sightings
		-- run on their own clock in the gaps
		local function anyoneInCity()
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Activity") == "city" then return true end
			end
			return false
		end
		local function headlineLive()
			for _, ev in live do
				if not ev.def.ambient then return true end
			end
			return false
		end
		-- `retry` drops the "not one of the last few" rule, which is the only
		-- one worth relaxing: minPlayers is a real requirement, so if nothing
		-- qualifies this returns nil and the caller waits rather than
		-- recursing forever.
		local function pickHeadline(retry)
			local n = cityCount()
			local pool, total = {}, 0
			for _, def in EV.List do
				if not def.ambient and n >= (def.minPlayers or 1)
					and (retry or not table.find(lastHeadline, def.id)) then
					table.insert(pool, def)
					total += def.weight or 10
				end
			end
			if #pool == 0 then
				if retry then return nil end
				table.clear(lastHeadline)
				return pickHeadline(true)
			end
			local r = math.random() * total
			for _, def in pool do
				r -= def.weight or 10
				if r <= 0 then return def end
			end
			return pool[#pool]
		end
		task.spawn(function()
			task.wait(EV.FirstAfter)
			while true do
				local def = (anyoneInCity() and not headlineLive()) and pickHeadline() or nil
				if def then
					table.insert(lastHeadline, def.id)
					-- with only a couple of headlines, "not the last three" would
					-- leave nothing to pick; never remember more than half the list
					local keep = 0
					for _, d in EV.List do if not d.ambient then keep += 1 end end
					while #lastHeadline > math.max(1, math.floor(keep / 2)) do table.remove(lastHeadline, 1) end
					local ev = start(def)
					while live[ev.uid] do task.wait(1) end
					task.wait(between(EV.Gap))
				else
					task.wait(5)
				end
			end
		end)
		task.spawn(function()
			task.wait(EV.FirstAfter * 0.5)
			while true do
				task.wait(between(EV.AmbientGap))
				local busy = false
				for _, ev in live do if ev.def.ambient then busy = true end end
				if anyoneInCity() and not busy then
					for _, def in EV.List do
						if def.ambient then start(def) break end
					end
				end
			end
		end)

		---------------------------------------------------------------------
		-- THE DAILY 3 (phase D). Three hidden Sminski whose LOTS are seeded
		-- from the UTC date, so they are the same three on every server and
		-- survive a restart with no persistence at all -- the spots are a pure
		-- function of the date. Find all three and the day pays a capsule
		-- ticket.
		--
		-- IT IS FIND'S GEOMETRY AND CLUES, NOT A ROW IN Config.Events.List.
		-- Three properties the director cannot express: the position is
		-- seeded, not random; the lifetime is the whole UTC day, not `lasts`;
		-- and every player may claim each spot once, recorded in the SAVE
		-- rather than in memory. Forcing that into an event row would mean
		-- special cases in start(), finish(), pickHeadline(), publicEv() and
		-- the reveal loop -- five, to avoid one small table. So this block
		-- sits beside the director, sharing its helpers and none of its
		-- lifecycle: no uid, not in `live`, never in the countdown strip,
		-- invisible to headlineLive() and to lastHeadline.
		--
		-- THE HUNT NEVER SENDS A COORDINATE IT HAS NOT EARNED. The tier
		-- NUMBER is derivable by anyone; the SENTENCE is not, and tier-3 text
		-- ahead of time hands a modded client the answer. So the text is built
		-- per player, per request, and `go` (the lot's DOOR, never the spot)
		-- only ever goes out at tier 3. The position itself is held back until
		-- the player is inside Hunt.Reveal, on the same reveal loop phase A
		-- uses.
		---------------------------------------------------------------------
		do
			local HU = Config.Hunt
			local M = Config.Meter

			-- One ticket, pushed to the player it was granted to, because a
			-- grant can land on a deferred or server-initiated payout whose
			-- reply the client never sees. This fills the forward slot that
			-- grantTicket() declared a thousand lines up.
			pushTicket = function(player, tickets, meter, from)
				evRemote:FireClient(player, "ticket", { tickets = tickets, meter = meter, from = from })
			end

			-----------------------------------------------------------------
			-- D1: THE LOTS THE HUNT MAY NOT USE.
			--
			-- E.prompt outranks every shop and business door -- but NOT
			-- City.Apts, City.Home, City.Roads or City.Hang
			-- (City.lua:2156-2170). A hunt Sminski standing where one of
			-- those wins is PERMANENTLY UNCLAIMABLE: the player stands on it,
			-- another module's prompt shows, and there is no way to say hello.
			-- So they leave the candidate pool by construction, the way phase
			-- B's scatter does. Reordering prompt priority would reorder
			-- interactions players already rely on and is not the fix.
			--
			-- WHICH ONES ACTUALLY REACH THE DOOR STRIP -- worked, not assumed.
			-- A hunt spot is at door + t*(+/-11) + n*2.5, i.e. 11.3 studs from
			-- the door at most, and always OUTSIDE it:
			--
			--   City.Apts   its doors are at the building's own front step,
			--               lot.pos + 17 (rowhouse) or + 21 (apartment), r =
			--               6, and the three towers' doors are set back behind
			--               the street wall. lot.pos is 36..40 studs INSIDE
			--               lot.door, so the nearest is 24 studs away. Clear.
			--   City.Home   frontDoor(lot) = lot.pos + 16, r = 8 -> 25 studs
			--               away by the same arithmetic. Clear. (Which is why
			--               houses stay in the pool: "by a house on Sunny St"
			--               is one of the clues the design asks for.)
			--   City.Hang   every spot is deep inside a block -- the concert
			--               lawn, the bandstand ring, the boardwalk out at
			--               z = 1010. Nearest to a door line is 36 studs.
			--   City.Roads  THE ONE THAT BITES, and it is not a lot kind. Each
			--               station drops a glass LIFT on the pavement at
			--               cf * (side*25.5, -y, -11) off the rail centreline,
			--               with an UP prompt at r = 7 -- and The Elevated
			--               runs down the middle of x/z = +/-600, which are
			--               ROADS, so those lifts land squarely in front of the
			--               lots either side. Measured for HOMETOWN: the lift
			--               bottom at (139, -574.5) is 4.0 studs from the
			--               apartment lot's own hunt spot, well inside 7.
			--               Eight lifts. EXCLUDED.
			--
			-- MEASURED AFTERWARDS, AND `blocked` IS SMALL ON PURPOSE. QA swept
			-- all 758 candidate spots (379 pooled lots x both sides): only TWO
			-- lot doors fall inside ExcludeR, so the dev hook reports blocked =
			-- 2, not the ten first estimated here. Do NOT read that as "the
			-- filter barely does anything" and delete it -- those two are the
			-- 4.0-stud spot above and its neighbour, and with them gone the
			-- nearest remaining spot to any lift is 26.31 studs, with zero
			-- inside the 7-stud prompt. The 26.31 is the number that proves the
			-- filter worked; a smaller ExcludeR starts letting the unclaimable
			-- ones back in.
			--
			-- Roads is a shared module with no Instance in it ("shared so the
			-- client and the server always agree on where things are", its own
			-- header), so the lift positions are DERIVED from the same three
			-- lines the client builds them with rather than copied as numbers.
			-- If it cannot be reached the hunt still runs, on the full pool,
			-- with a warning -- a missing module must not take the city down.
			-----------------------------------------------------------------
			local blockers = {}
			do
				local shared = ReplicatedStorage:FindFirstChild("SminskiShared")
				local mod = shared and shared:FindFirstChild("Roads")
				local okReq, Roads = pcall(function() return mod and require(mod) or nil end)
				if okReq and type(Roads) == "table" and type(Roads.stations) == "table" then
					local okGeo = pcall(function()
						for _, st in Roads.stations do
							local s0 = Roads.nearest("rail", st.pos)
							local pos, dir = Roads.at("rail", s0)
							-- city-relative, exactly as CityRoads builds it in
							-- world space; the rotation is the same either way
							local cf = CFrame.lookAt(pos, pos + dir)
							for _, side in { -1, 1 } do
								local lift = (cf * CFrame.new(side * 25.5, -pos.Y, -11)).Position
								table.insert(blockers, Vector3.new(lift.X, 0, lift.Z))
							end
						end
					end)
					if not okGeo then
						table.clear(blockers)
						warn("[hunt] could not derive the station lifts; the Daily 3 pool is unfiltered")
					end
				else
					warn("[hunt] Roads unavailable; the Daily 3 pool is unfiltered")
				end
			end

			local pool = {}
			do
				local r2 = (HU.ExcludeR or 24) ^ 2
				for _, lot in streetLots do
					local ok = true
					for _, b in blockers do
						local dx, dz = lot.door.X - b.X, lot.door.Z - b.Z
						if dx * dx + dz * dz < r2 then ok = false break end
					end
					if ok then table.insert(pool, lot) end
				end
				-- never leave the hunt with nothing to pick
				if #pool < HU.Count then pool = streetLots end
			end

			-----------------------------------------------------------------
			-- SEEDING. A PER-LOT HASH, NOT THREE RANDOM INDICES.
			--
			-- streetLots is derived from Places.cityLots(), which is
			-- append-only BECAUSE SAVES STORE INDICES INTO IT (assignHouse,
			-- Places.lua:280-282). An index-based seed would move today's
			-- answer the moment a lot is appended; a per-lot hash of the
			-- lot's own GEOMETRY only moves if a newly added lot's hash lands
			-- in the accepted three (~0.8% per lot added) and never for lots
			-- that already exist. Nothing in phase D persists a lot index.
			--
			-- Cost: ~380 hashes and a sort, once per UTC day per server.
			-----------------------------------------------------------------
			local function lotKey(lot)
				return string.format("%d,%d", math.round(lot.door.X), math.round(lot.door.Z))
			end

			local function spotFrom(lot, score)
				-- THE MEASURED FORMULA (docs/HANDOFF.md section 5), with a
				-- deterministic side: -1.5 is inside the shop window, +2.5 in
				-- front of the door measured 6/6 clear with the back to the
				-- glass, +15.3 is the kerb gutter.
				local n = Vector3.new(math.sin(lot.face), 0, math.cos(lot.face))
				local t = Vector3.new(n.Z, 0, -n.X)
				local side = (score % 2 == 0) and -1 or 1
				return {
					lot = lot, side = side, face = lot.face,
					pos = lot.door + t * side * 11 + n * 2.5,
					revealed = {},
				}
			end

			local function seed(key)
				local scored = {}
				for _, lot in pool do
					local lk = lotKey(lot)
					table.insert(scored, { lot = lot, key = lk, score = hashKey("hunt|" .. key .. "|" .. lk) })
				end
				-- lotKey breaks hash ties, so the order is total and identical
				-- on every server
				table.sort(scored, function(a, b)
					if a.score ~= b.score then return a.score < b.score end
					return a.key < b.key
				end)
				local out = {}
				local spread2 = (HU.Spread or 500) ^ 2
				local function tryAdd(e, checkSpread)
					if #out >= HU.Count then return end
					for _, chosen in out do
						if chosen.lot == e.lot then return end
						if checkSpread then
							local dx, dz = e.lot.door.X - chosen.lot.door.X, e.lot.door.Z - chosen.lot.door.Z
							if dx * dx + dz * dz < spread2 then return end
						end
					end
					table.insert(out, spotFrom(e.lot, e.score))
				end
				for _, e in scored do tryAdd(e, true) end
				-- the greedy spread rule can come up short on a thin pool; top
				-- up from the head of the SAME sorted list rather than leave a
				-- nil hole, so the three stay a pure function of the date
				for _, e in scored do tryAdd(e, false) end
				return out
			end

			-----------------------------------------------------------------
			-- THE DAY. Whole seconds, rounded once: os.time() and the day key
			-- are the class of thing that loses a minute to
			-- 23.99999999999992 if it is allowed to stay a float.
			-----------------------------------------------------------------
			local function endsOf(key)
				local y, m, d = string.match(tostring(key), "^(%d+)%-(%d+)%-(%d+)$")
				if y then
					local okT, t = pcall(os.time, { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
					if okT and type(t) == "number" then
						t = math.floor(t)
						return t - t % 86400 + 86400
					end
				end
				local t = math.floor(os.time())
				return t - t % 86400 + 86400
			end
			-- the day before a key, derived FROM THE KEY and not from the
			-- clock, so the streak still behaves under the Studio day hooks
			local function prevKey(key)
				local y, m, d = string.match(tostring(key), "^(%d+)%-(%d+)%-(%d+)$")
				if not y then return "" end
				local okT, t = pcall(os.time, { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
				if not okT or type(t) ~= "number" then return "" end
				return os.date("!%Y-%m-%d", math.floor(t) - 86400)
			end

			local today = { day = nil, ends = 0, spots = {}, here = {} }
			local pinned = nil        -- Studio only: a forced day key
			local pendingReset = false

			local function reseed(key)
				today.day = key
				today.ends = endsOf(key)
				today.spots = seed(key)
				today.here = {}
				for i = 1, HU.Count do today.here[i] = 0 end
				pendingReset = true
			end
			-- Seeds if the UTC day has turned over. It is called from the 1 Hz
			-- loop AND from pickSpot/scatter, which can run first, so the
			-- broadcast is a flag the tick consumes rather than something a
			-- director thread can end up doing.
			local function ensureDay()
				local key = pinned or os.date("!%Y-%m-%d")
				if today.day ~= key then reseed(key) end
			end

			-----------------------------------------------------------------
			-- CLUES. Tier 1 a district, tier 2 the street and the thing on it,
			-- tier 3 a compass bearing off the nearest landmark as well.
			--
			-- TIER 2 IS THE SHAREABLE STRING -- "on Birch Ave, by the FLORIST"
			-- is what a player types into chat -- which is exactly why the
			-- tier function counts OTHER players' finds: being near someone
			-- else makes the hunt materially easier.
			-----------------------------------------------------------------
			local KINDS = {
				house = "a house", rowhouse = "a house", apartment = "the apartments",
				jobcentre = "the Job Center", shop = "a shop", midrise = "a shop",
				corner = "a shop", venue = "a cafe",
			}
			local function thing(lot)
				if type(lot.name) == "string" and lot.name ~= "" then return "the " .. lot.name end
				return KINDS[lot.kind] or "a doorway"
			end
			local function tierOf(i, mine)
				-- your own finds, plus up to two of this server's finds of
				-- THIS spot. Solo always reaches tier 3 on the last one.
				return math.clamp(1 + mine + math.min(today.here[i] or 0, 2), 1, 3)
			end
			local function tier2Of(sp)
				return "on " .. streetOf(sp.lot) .. ", by " .. thing(sp.lot)
			end
			local function clueFor(i, tier)
				local sp = today.spots[i]
				if not sp then return "" end
				if tier <= 1 then return "somewhere in " .. areaOf(sp.lot, sp.pos) end
				local t2 = tier2Of(sp)
				if tier == 2 then return t2 end
				local lm = nearestLandmark(sp.pos)
				return compass(lm.pos, sp.pos) .. " of " .. lm.name .. ", " .. t2
			end
			-- the compact screen's line. Measured longest: tier 1 "somewhere in
			-- the entertainment district" = 39, tier 2 "on Central Blvd, by the
			-- SANDWICH BAR" = 36 -- both inside the 44 the phone allows, and
			-- tier 3 falls back to its tier-2 half rather than ellipsising.
			local function shortFor(i, tier)
				local sp = today.spots[i]
				if not sp then return nil end
				if tier >= 3 then return tier2Of(sp) end
				return clueFor(i, tier)
			end
			-- a short place phrase for the feed and the broadcast, <= 22 chars
			-- ("the entertainment one" is the longest at 21)
			local function whereOf(sp)
				local d = sp.lot.district
				if type(d) == "string" and d ~= "" then return "the " .. d .. " one" end
				return "the " .. compass(Vector3.zero, sp.pos) .. " one"
			end

			-----------------------------------------------------------------
			-- STATE. `found` is DENSE, three booleans, every time it leaves
			-- here -- see the note in saved().
			-----------------------------------------------------------------
			local function denseFound(h)
				local out = {}
				for i = 1, HU.Count do out[i] = h.found[i] == true end
				return out
			end
			-- the player's own row, rolled over to today if their save is old
			local function mineOf(s)
				local c = saved(s)
				local h = c.hunt
				if h.day ~= today.day then
					h.day = today.day
					local f = {}
					for i = 1, HU.Count do f[i] = false end
					h.found = f
				end
				local n = 0
				for i = 1, HU.Count do if h.found[i] then n += 1 end end
				return h, n, c
			end
			local function spotsFor(mine)
				local out = {}
				for i = 1, HU.Count do
					local sp = today.spots[i]
					if sp then
						local tier = tierOf(i, mine)
						out[i] = {
							tier = tier, clue = clueFor(i, tier), clueShort = shortFor(i, tier),
							here = today.here[i] or 0,
							-- the GO ribbon points at the lot's DOOR, never at
							-- the spot: the last 11 studs stay yours to find
							go = tier >= 3 and { x = sp.lot.door.X, z = sp.lot.door.Z } or nil,
						}
					else
						out[i] = { tier = 1, clue = "", here = 0 }
					end
				end
				return out
			end
			local function blockFor(s)
				local h, mine = mineOf(s)
				return {
					day = today.day, ends = today.ends, found = denseFound(h),
					streak = h.streak or 0, full = mine >= HU.Count, spots = spotsFor(mine),
				}
			end

			local function inCity(player)
				return player:GetAttribute("Activity") == "city"
			end
			-- every player whose clue set may have moved, except the finder,
			-- who gets `spots` in their own reply
			local function pushClues(except)
				for _, player in Players:GetPlayers() do
					if player ~= except and inCity(player) then
						local s2 = sessions[player]
						if s2 then evRemote:FireClient(player, "huntClues", blockFor(s2)) end
					end
				end
			end
			-- the day turned over: drop every model, then hand out the new day
			local function broadcastReset()
				for _, player in Players:GetPlayers() do
					local s2 = sessions[player]
					if s2 then
						-- ROLL THE DAY CAP HERE TOO, for the player sitting in
						-- the city across midnight. meterAdd() and grantTicket()
						-- are the authoritative checks and they recompute the day
						-- themselves, so this changes no rule -- but until one of
						-- them next runs, a capped player's client would keep
						-- reading meterDayTickets = 12 and showing "all earned
						-- today". This is the one place that already fires exactly
						-- once per day boundary and already walks every session,
						-- so closing that window costs nothing.
						rollMeterDay(s2)
						for i = 1, HU.Count do evRemote:FireClient(player, "huntHide", { i = i }) end
						evRemote:FireClient(player, "huntReset", blockFor(s2))
					end
				end
			end

			-----------------------------------------------------------------
			-- THE CLAIM. Distance-checked against where the character really
			-- is, once per player per UTC day, recorded in the save.
			-----------------------------------------------------------------
			local function claim(player, s, arg)
				-- if this call is the first thing to notice the rollover, the
				-- spots under it have just changed and the claim was aimed at
				-- yesterday's. Say so; do not distance-check it against a spot
				-- the player has never seen and call them too far away.
				local was = today.day
				ensureDay()
				if was ~= nil and was ~= today.day then
					return { ok = false, reason = "it's a new day -- look again" }
				end
				local i = math.floor(tonumber(arg) or 0)
				if i < 1 or i > HU.Count then return { ok = false } end
				local sp = today.spots[i]
				if not sp then return { ok = false } end
				-- SNAPSHOT WHAT IS BEING TESTED, AT THE MOMENT IT IS TRUE.
				-- mineOf() rolls the save over to today, so the stale-day test
				-- has to be read BEFORE it: a client holding yesterday's clue
				-- set is told so, rather than being distance-checked against a
				-- spot it has never seen and told "too far away". Everything
				-- below is decided against the one key read here, so a claim
				-- landing exactly on the boundary pays exactly once.
				local c0 = saved(s)
				local stale = c0.hunt.day ~= "" and c0.hunt.day ~= today.day
				local h, mine, c = mineOf(s)
				local day = today.day
				if stale then return { ok = false, reason = "it's a new day -- look again" } end
				if h.found[i] then return { ok = false, reason = "already found today" } end
				local pos = cityPos(player)
				if not pos or (pos - sp.pos).Magnitude > (HU.Claim or 12) then
					return { ok = false, reason = "too far away" }
				end

				----- no yield from here --------------------------------------
				h.found[i] = true
				mine += 1
				local first = (today.here[i] or 0) == 0
				today.here[i] = (today.here[i] or 0) + 1
				local base = (HU.Rewards[mine] or HU.Rewards[#HU.Rewards] or 0)
					+ (first and (HU.FirstHere or 0) or 0)
				local xp = HU.Xp[mine] or HU.Xp[#HU.Xp] or 0
				-- "Hunt" is on the meter whitelist, so the hunt fills the meter
				-- like any other work, and passes multiply the coins like any
				-- other find. The TICKET is multiplied by nothing.
				local coins = pay(player, s, base, xp, "Hunt")
				local ticket, streakTicket
				if mine >= (HU.TicketAt or HU.Count) then
					-- GRANTED EVEN AT DayCap AND EVEN AT MaxTickets. A
					-- once-a-day reward that silently does not arrive is worse
					-- than any cap it protects, so c.tickets may go past
					-- MaxTickets here. Do not clamp it.
					grantTicket(player, s, "hunt")
					ticket = true
					if h.lastFull ~= day then
						h.streak = (h.lastFull == prevKey(day)) and (h.streak or 0) + 1 or 1
						h.lastFull = day
						if (HU.StreakDays or 0) > 0 and h.streak % HU.StreakDays == 0 then
							grantTicket(player, s, "streak")
							streakTicket = true
						end
					end
				end
				----- to here ------------------------------------------------

				if mine >= HU.Count then
					feed(player.DisplayName .. " found all three of today's hidden Sminski!", "rare")
				else
					feed(player.DisplayName .. " found " .. whereOf(sp) .. " of today's three!", "info")
				end
				-- TEXT ONLY. No coordinates leave here.
				evRemote:FireAllClients("huntFound", { i = i, who = player.DisplayName, where = whereOf(sp), first = first })
				-- only the first two finds of a spot can move anybody's tier
				if today.here[i] <= 2 then pushClues(player) end
				task.spawn(save, player)
				return {
					ok = true, coins = coins, xp = xp, first = first,
					found = denseFound(h), mine = mine,
					ticket = ticket, tickets = c.tickets,
					streak = h.streak or 0, streakTicket = streakTicket,
					spots = spotsFor(mine),
					data = publicData(s), city = public(s),
				}
			end

			-----------------------------------------------------------------
			-- THE 1 Hz PASS. Day rollover, then one reveal check per spot.
			-----------------------------------------------------------------
			local function tick()
				ensureDay()
				if pendingReset then
					pendingReset = false
					broadcastReset()
				end
				for i = 1, HU.Count do
					local sp = today.spots[i]
					if sp then
						for _, player in Players:GetPlayers() do
							if not sp.revealed[player.UserId] then
								local s2 = sessions[player]
								local pos = s2 and cityPos(player)
								if pos and (pos - sp.pos).Magnitude <= (HU.Reveal or 90) then
									local h = mineOf(s2)
									if not h.found[i] then
										sp.revealed[player.UserId] = true
										-- KEY-SHAPED, NOT POSITIONAL, AND THE
										-- DIFFERENCE IS THE WHOLE FEATURE. Every
										-- hunt payload is read by KEY on the client
										-- (spot.x / spot.z / spot.face,
										-- CityEvents.lua:1260 and :1271), so the
										-- array form { X, Z, face } arrives as three
										-- nils and not one hunt Sminski is ever
										-- drawn -- silently, with no error anywhere.
										-- Phase A's secret() at :2647 IS positional
										-- and IS correct, because phase A's client
										-- unpacks it positionally. Two shapes, two
										-- consumers, one file: do not "unify" them.
										evRemote:FireClient(player, "huntReveal", {
											i = i,
											spot = { x = sp.pos.X, z = sp.pos.Z, face = sp.face },
										})
									end
								end
							end
						end
					end
				end
			end

			huntTick = tick
			huntLotTaken = function(lot)
				ensureDay()
				for _, sp in today.spots do
					if sp.lot == lot then return true end
				end
				return false
			end
			huntNear = function(x, z, r2)
				ensureDay()
				for _, sp in today.spots do
					local dx, dz = x - sp.pos.X, z - sp.pos.Z
					if dx * dx + dz * dz < r2 then return true end
				end
				return false
			end
			huntPublic = function(player, s, fresh)
				ensureDay()
				if fresh then
					-- the client has just rebuilt the city, so its models are
					-- gone: forget the reveals and let the next tick resend
					for _, sp in today.spots do sp.revealed[player.UserId] = nil end
				end
				return blockFor(s)
			end
			huntClaimFn = claim

			-----------------------------------------------------------------
			-- STUDIO ONLY. QA cannot wait a day for a rollover or grind ten
			-- minutes for a ticket, and a feature QA cannot trigger cannot be
			-- verified. Wired into the existing EventsDev remote below.
			-----------------------------------------------------------------
			if RunService:IsStudio() then
				local devDays = 0
				local function summary()
					local out = {}
					for i, sp in today.spots do
						out[i] = {
							i = i, x = sp.pos.X, z = sp.pos.Z, face = sp.face, side = sp.side,
							doorX = sp.lot.door.X, doorZ = sp.lot.door.Z,
							kind = sp.lot.kind, name = sp.lot.name, street = streetOf(sp.lot),
							district = sp.lot.district,
							tier1 = clueFor(i, 1), tier2 = clueFor(i, 2), tier3 = clueFor(i, 3),
						}
					end
					local gaps = {}
					for a = 1, #today.spots do
						for b = a + 1, #today.spots do
							table.insert(gaps, math.round((today.spots[a].pos - today.spots[b].pos).Magnitude))
						end
					end
					return out, gaps
				end

				huntDev = function(player, cmd, arg)
					local s = sessions[player]
					if not s then return { ok = false, reason = "no session" } end
					ensureDay()
					local c = saved(s)

					if cmd == "meterAdd" then
						-- THROUGH THE REAL GRANT PATH. The ceiling is not
						-- bypassed, it is fast-forwarded: each pass back-dates
						-- the allowance clock by exactly one minute, which is
						-- what waiting a minute would do, and credits at most
						-- one Burst. So the per-minute clamp, DayCap,
						-- MaxTickets, the park-below-full rule, the ticket
						-- grant, the CityEvent push and the save all run for
						-- real. Writing c.meter directly would prove nothing.
						local n = math.clamp(math.floor(tonumber(arg) or 0), 0, 100000)
						local before = c.tickets
						local left, guard = n, 0
						while left > 0 and guard < 4000 do
							guard += 1
							s.meterAllow = 0
							s.meterT = os.clock() - 60
							local step = math.min(left, M.Burst)
							meterAdd(player, s, step)
							left -= step
						end
						return { ok = true, added = n, meter = c.meter, tickets = c.tickets,
							granted = c.tickets - before, meterDay = c.meterDay,
							meterDayTickets = c.meterDayTickets, dayCap = M.DayCap,
							maxTickets = M.MaxTickets, ticket = M.Ticket }
					end

					if cmd == "huntSeed" then
						-- GEOMETRY SAMPLING, NOT A DAY ROLL. It pins the hunt's
						-- spots to an arbitrary key -- including a past one -- and
						-- deliberately leaves devDayShift alone, so the METER's day
						-- does not move. That means `day` and `meterDay` in the
						-- reply can legitimately differ after a huntSeed; use
						-- huntReset, not huntSeed, when the test is about the
						-- rollover. Both are reported so a divergence is visible
						-- rather than confusing.
						local key = tostring(arg or "")
						if not string.match(key, "^%d%d%d%d%-%d%d%-%d%d$") then key = os.date("!%Y-%m-%d") end
						pinned = key
						reseed(key)
						pendingReset = false
						broadcastReset()
						local spots, gaps = summary()
						return { ok = true, day = key, ends = today.ends, spots = spots,
							gaps = gaps, spread = HU.Spread, pool = #pool, blocked = #streetLots - #pool,
							meterDay = c.meterDay, meterDayTickets = c.meterDayTickets }
					end

					if cmd == "huntReset" then
						-- ONE WHOLE UTC DAY FORWARD FOR THE HUNT *AND* FOR THE
						-- METER, each call. It advances one day counter and both
						-- systems read it, because "the day rolled over" is one
						-- event and two hooks that could disagree about the date
						-- would be worse than none.
						--
						-- devDayShift is what makes rollMeterDay() run FOR REAL:
						-- the hook moves the clock, and the production function
						-- notices and zeroes meterDayTickets by itself.
						-- broadcastReset() below already calls rollMeterDay() for
						-- every session, so the shift is applied BEFORE it --
						-- nothing here writes meterDay or meterDayTickets, and a
						-- hook that did would prove nothing about the rollover.
						--
						-- It deliberately does NOT reset c.meter, because the real
						-- rollover does not either: only meterDayTickets is
						-- per-day, and the sub-ticket remainder is earned progress.
						devDays += 1
						devDayShift = devDays
						local t = math.floor(os.time()) + devDays * 86400
						pinned = os.date("!%Y-%m-%d", t)
						reseed(pinned)
						pendingReset = false
						broadcastReset()
						local spots, gaps = summary()
						return { ok = true, day = pinned, ends = today.ends, spots = spots,
							gaps = gaps, daysForward = devDays,
							-- read these back to assert the roll actually happened
							meterDay = c.meterDay, meterDayTickets = c.meterDayTickets,
							meter = c.meter, tickets = c.tickets }
					end

					if cmd == "streakSet" then
						local n = math.clamp(math.floor(tonumber(arg) or 0), 0, 9999)
						local h = mineOf(s)
						h.streak = n
						-- and make the NEXT 3/3 continue the run instead of
						-- restarting it, relative to the day in play
						h.lastFull = n > 0 and prevKey(today.day) or ""
						task.spawn(save, player)
						return { ok = true, streak = h.streak, lastFull = h.lastFull,
							day = today.day, streakDays = HU.StreakDays }
					end

					return { ok = false, reason = "unknown hunt dev command" }
				end
			end
		end

		-- Studio only: start one on demand instead of waiting out the schedule,
		-- plus the two collect paths that cannot be reached from one client.
		--
		--   EventsDev:InvokeServer(id, atMe)          start it now
		--   EventsDev:InvokeServer("raceTest", uid, itemId)
		--   EventsDev:InvokeServer("endNow", uid)
		-- and phase D, where waiting for a UTC rollover or grinding ten minutes
		-- is not a test plan:
		--   EventsDev:InvokeServer("meterAdd", units)      -> meter, tickets
		--   EventsDev:InvokeServer("huntSeed", "2026-09-21") -> the three spots
		--   EventsDev:InvokeServer("huntReset")            -> one day forward
		--   EventsDev:InvokeServer("streakSet", n)         -> the hunt streak
		if RunService:IsStudio() then
			local HUNT_DEV = { meterAdd = true, huntSeed = true, huntReset = true, streakSet = true }
			rf("EventsDev").OnServerInvoke = function(player, id, atMe, itemId)
				local key = tostring(id)

				if HUNT_DEV[key] then
					if not huntDev then return { ok = false, reason = "the hunt did not initialise" } end
					return huntDev(player, key, atMe)
				end

				-- Two claims for one bag, resolved against each other rather
				-- than one after the other: both are deferred, so neither runs
				-- at the point it is created and the scheduler decides. Exactly
				-- one may come back ok; the other must say "already gone", and
				-- the caller's coins must move exactly once.
				if key == "raceTest" then
					local s = session(player)
					local ev = live[tonumber(atMe) or -1]
					if not s or not ev or ev.def.kind ~= "collect" then
						return { ok = false, reason = "no live collect event with that uid" }
					end
					local before = s.data.Coins
					local ra, rb, da, db
					task.defer(function() ra = collectClaim(player, s, ev, itemId) da = true end)
					task.defer(function() rb = collectClaim(player, s, ev, itemId) db = true end)
					local t0 = os.clock()
					while not (da and db) and os.clock() - t0 < 5 do task.wait() end
					-- `paid` is the whole point: it must equal one item's pay,
					-- never two, whatever the two replies say
					return { ok = true, a = ra, b = rb, got = ev.got,
						coinsBefore = before, coinsAfter = s.data.Coins, paid = s.data.Coins - before }
				end

				-- End one now, so the after-the-event claim path is testable
				-- in seconds instead of in three minutes.
				if key == "endNow" then
					local ev = live[tonumber(atMe) or -1]
					if not ev then return { ok = false, reason = "no live event with that uid" } end
					if ev.def.kind == "collect" and not ev.over then
						finishCollect(ev, "time")
					else
						finish(ev)
					end
					return { ok = true, uid = ev.uid, ended = true }
				end

				local def = Config.Event(key)
				if not def then return { ok = false } end
				-- for a collect event `atMe` has to be honoured BEFORE the
				-- scatter, because the zone centre decides where the items go
				local centre
				if atMe and def.kind == "collect" then
					local p = cityPos(player)
					if p then
						local bd
						for _, c in centreLots do
							local d = (c.lot.door - p).Magnitude
							if not bd or d < bd then centre, bd = c, d end
						end
					end
				end
				local ev = start(def, centre)
				if atMe and def.kind ~= "collect" then
					-- drop it 40 studs from the caller so a test does not have to
					-- cross town; the claim check still has to be walked
					local pos = cityPos(player)
					if pos then ev.pos = pos + Vector3.new(40, 0, 0) end
				end
				ev.startT = now()
				ev.endT = ev.startT + def.lasts
				if not ev.quiet then evRemote:FireAllClients("start", publicEv(ev)) end
				local out = { ok = true, uid = ev.uid, pos = { ev.pos.X, ev.pos.Z } }
				if ev.items then
					-- EVERY item, taken or not, so QA can sample real positions
					-- and measure the spacing instead of guessing at it
					local list = {}
					for _, it in ev.items do
						table.insert(list, { id = it.id, x = it.pos.X, z = it.pos.Z })
					end
					out.items = list
					out.got, out.goal, out.left, out.count = ev.got, ev.goal, ev.left, ev.total
				end
				return out
			end
		end
	end

end
