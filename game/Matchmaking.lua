-- Matchmaking (ServerScriptService.SminskiServer.Matchmaking)
-- Friend lobbies (5-letter codes), quick play + ranked queues, and the
-- multiplayer match itself: Resurgence-style respawns, shoves, Elo.
--
-- Matches run inside whatever server the players are already in (every
-- player's world is built on their own machine from a shared seed), so
-- friends in one server and Studio multi-client tests need no teleports.
-- In the live game, queued players in different servers are grouped through
-- MemoryStore and sent to a reserved server together.

return function(api)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local TeleportService = game:GetService("TeleportService")
	local MemoryStoreService = game:GetService("MemoryStoreService")
	local MessagingService = game:GetService("MessagingService")
	local HttpService = game:GetService("HttpService")

	local Config = api.Config
	local MP = Config.MP
	local IS_STUDIO = RunService:IsStudio()
	local IS_MATCH_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

	local function now()
		return workspace:GetServerTimeNow()
	end

	---------------------------------------------------------------------------
	-- REMOTES
	---------------------------------------------------------------------------
	local folder = Instance.new("Folder")
	folder.Name = "SminskiMP"
	local Request = Instance.new("RemoteFunction")
	Request.Name = "Request"
	Request.Parent = folder
	local Event = Instance.new("RemoteEvent")
	Event.Name = "Event"
	Event.Parent = folder
	local Action = Instance.new("RemoteEvent")
	Action.Name = "Action"
	Action.Parent = folder
	local State = Instance.new("UnreliableRemoteEvent")
	State.Name = "State"
	State.Parent = folder
	folder:SetAttribute("MatchServer", IS_MATCH_SERVER)
	folder.Parent = ReplicatedStorage

	local function eloOf(player)
		local s = api.sessions[player]
		return s and s.data.Elo or MP.StartElo
	end

	local function playerInfo(player)
		local s = api.sessions[player]
		local elo = eloOf(player)
		local tier = Config.RankTier(elo)
		return {
			userId = player.UserId,
			name = player.DisplayName,
			char = s and s.data.EquippedCharacter or "Glow",
			outfit = s and s.data.EquippedOutfit or "None",
			elo = elo,
			tier = tier.id,
		}
	end

	-- optional cross-server stores (fail quietly in Studio without API access)
	local queueMap, lobbyMap
	pcall(function()
		queueMap = MemoryStoreService:GetSortedMap("SmiskiQueue_v1")
		lobbyMap = MemoryStoreService:GetSortedMap("SmiskiLobbies_v1")
	end)
	local crossServer = not IS_STUDIO and queueMap ~= nil

	---------------------------------------------------------------------------
	-- STATE
	---------------------------------------------------------------------------
	local lobbies = {} -- code -> { code, host, members = {player} }
	local lobbyOf = {} -- player -> code
	local queue = {} -- player -> { ranked, t0, published }
	local leaveMatchRef -- set once leaveMatch is defined (the request handler sits above it)
	local matches = {} -- id -> match
	local matchOf = {} -- player -> match

	local function sendStatus(player)
		local q = queue[player]
		local code = lobbyOf[player]
		local l = code and lobbies[code]
		local lobby
		if l then
			lobby = { code = l.code, host = l.host.UserId, members = {}, map = l.map or "house" }
			for _, m in l.members do
				table.insert(lobby.members, playerInfo(m))
			end
		end
		Event:FireClient(player, "status", {
			lobby = lobby,
			queue = q and { ranked = q.ranked, since = q.t0 } or nil,
			inMatch = matchOf[player] ~= nil,
			matchServer = IS_MATCH_SERVER,
		})
	end

	local function pushLobby(l)
		for _, m in l.members do
			sendStatus(m)
		end
	end

	---------------------------------------------------------------------------
	-- LOBBIES
	---------------------------------------------------------------------------
	local CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	local function newCode()
		for _ = 1, 50 do
			local c = ""
			for _ = 1, 5 do
				local i = math.random(1, #CODE_CHARS)
				c ..= CODE_CHARS:sub(i, i)
			end
			if not lobbies[c] then return c end
		end
		return HttpService:GenerateGUID(false):sub(1, 5):upper()
	end

	local function leaveQueue(player)
		local q = queue[player]
		queue[player] = nil
		if q and q.published and queueMap then
			task.spawn(pcall, queueMap.RemoveAsync, queueMap, tostring(player.UserId))
		end
	end

	local function leaveLobby(player)
		local code = lobbyOf[player]
		if not code then return end
		lobbyOf[player] = nil
		local l = lobbies[code]
		if not l then return end
		local i = table.find(l.members, player)
		if i then table.remove(l.members, i) end
		if #l.members == 0 then
			lobbies[code] = nil
			if lobbyMap and not IS_STUDIO then
				task.spawn(pcall, lobbyMap.RemoveAsync, lobbyMap, code)
			end
		else
			if l.host == player then l.host = l.members[1] end
			pushLobby(l)
		end
		if player.Parent then sendStatus(player) end
	end

	local function joinLocalLobby(player, code)
		local l = lobbies[code]
		if not l then return false, "no lobby with that code" end
		if #l.members >= MP.MaxPlayers then return false, "that lobby is full" end
		if table.find(l.members, player) then return true end
		leaveQueue(player)
		leaveLobby(player)
		table.insert(l.members, player)
		lobbyOf[player] = code
		pushLobby(l)
		return true
	end

	---------------------------------------------------------------------------
	-- MATCHES
	---------------------------------------------------------------------------
	local function aliveCount(m)
		local n = 0
		for _, st in m.list do
			if st.alive and not st.gone then n += 1 end
		end
		return n
	end

	local function fireMatch(m, kind, payload)
		for _, st in m.list do
			if not st.bot and not st.gone and st.player.Parent then
				Event:FireClient(st.player, kind, payload)
			end
		end
	end

	local function endMatch(m, reason)
		if m.over then return end
		m.over = true
		local elapsed = math.max(1, now() - m.startAt)

		local rows = table.clone(m.list)
		table.sort(rows, function(a, b)
			return (a.stats.score or 0) > (b.stats.score or 0)
		end)

		-- pairwise Elo over finishing order
		local deltas = {}
		local rankedGame = m.ranked and #rows >= 2
		if rankedGame then
			for i, a in rows do
				local sum = 0
				for j, b in rows do
					if i ~= j then
						local expected = 1 / (1 + 10 ^ ((b.elo - a.elo) / 400))
						local actual = (a.stats.score or 0) == (b.stats.score or 0) and 0.5 or (i < j and 1 or 0)
						sum += actual - expected
					end
				end
				deltas[a] = math.floor(MP.EloK * sum / (#rows - 1) + 0.5)
			end
		end

		local results = {}
		for place, st in rows do
			local p = st.player
			local s = not st.bot and p.Parent and api.sessions[p]
			local reward
			if s then
				reward = api.award(p, s, st.stats, elapsed)
				s.data.MatchesPlayed += 1
				if rankedGame then
					s.data.Elo = math.max(0, s.data.Elo + (deltas[st] or 0))
					s.data.PeakElo = math.max(s.data.PeakElo, s.data.Elo)
					s.data.RankedPlayed += 1
					if place == 1 then s.data.RankedWins += 1 end
				end
				reward.data = api.publicData(s)
			end
			st.reward = reward
			table.insert(results, {
				userId = st.userId,
				name = st.name,
				place = place,
				score = reward and reward.score or math.floor(st.stats.score or 0),
				distance = reward and reward.distance or (st.stats.distance or 0),
				eloDelta = deltas[st],
				elo = s and s.data.Elo or st.elo,
				left = st.gone and not st.bot,
				bot = st.bot,
			})
		end

		for _, st in m.list do
			if st.bot then continue end
			matchOf[st.player] = nil
			if not st.gone and st.player.Parent then
				Event:FireClient(st.player, "matchEnd", {
					reason = reason,
					ranked = rankedGame,
					results = results,
					reward = st.reward,
					you = st.userId,
				})
				sendStatus(st.player)
			end
		end
		matches[m.id] = nil
	end

	local BOT_NAMES = { "Mochi", "Pebble", "Bean", "Tofu", "Sprout", "Nori", "Peanut", "Dumpling", "Pudding", "Button", "Clover", "Gummy" }

	local function startMatch(players, ranked, seed, botCount, mapId)
		botCount = ranked and 0 or (botCount or 0)
		local m = {
			map = (not ranked and mapId) or "house",
			id = HttpService:GenerateGUID(false),
			ranked = ranked and #players >= 2,
			seed = seed or math.random(1, 2 ^ 30),
			startAt = now() + MP.CountdownLead,
			players = {},
			list = {},
			over = false,
		}
		local infos = {}
		for i, p in players do
			leaveQueue(p)
			local info = playerInfo(p)
			info.lane = MP.StartLanes[i] or 3
			table.insert(infos, info)
			local st = {
				player = p,
				userId = p.UserId,
				name = p.DisplayName,
				lane = info.lane,
				alive = true,
				gone = false,
				respawns = 0,
				stats = { score = 0, distance = 0, coins = 0, nearMisses = 0, bestCombo = 1 },
				elo = info.elo,
				lastShove = 0,
			}
			m.players[p] = st
			table.insert(m.list, st)
			matchOf[p] = m
		end
		if api.feed then
			local names = {}
			for _, p in players do table.insert(names, p.DisplayName) end
			api.feed(table.concat(names, " + ") .. (m.ranked and " started a RANKED run" or " started a squad run"), "squad")
		end
		-- bots are simulated by the first player's client and relayed like everyone else
		local host = players[1]
		local avgElo = 0
		for _, st in m.list do avgElo += st.elo end
		avgElo = avgElo / math.max(1, #m.list)
		local names = table.clone(BOT_NAMES)
		for b = 1, math.min(botCount, MP.MaxPlayers - #players) do
			local id = -b
			local nameIdx = math.random(1, #names)
			local name = table.remove(names, nameIdx)
			local char = Config.Characters[math.random(1, #Config.Characters)]
			local outfit = math.random() < 0.6 and Config.Outfits[math.random(2, #Config.Outfits)].id or "None"
			local lane = MP.StartLanes[#m.list + 1] or 3
			local info = {
				userId = id, name = name, char = char.id, outfit = outfit,
				elo = math.floor(avgElo), tier = Config.RankTier(avgElo).id, lane = lane,
				isBot = true, controller = host.UserId, skill = 0.35 + math.random() * 0.5,
			}
			table.insert(infos, info)
			local st = {
				bot = true, controller = host, userId = id, name = name, lane = lane,
				alive = true, gone = false, respawns = 0,
				stats = { score = 0, distance = 0, coins = 0, nearMisses = 0, bestCombo = 1 },
				elo = info.elo, lastShove = 0,
			}
			table.insert(m.list, st)
		end
		matches[m.id] = m
		m.infos = infos
		fireMatch(m, "matchStart", { id = m.id, seed = m.seed, startAt = m.startAt, ranked = m.ranked, players = infos, map = m.map })
		for _, p in players do sendStatus(p) end
		return m
	end

	local function findSt(m, userId)
		for _, st in m.list do
			if st.userId == userId then return st end
		end
		return nil
	end

	local function sanitizeStats(stats)
		if type(stats) ~= "table" then return nil end
		local out = {}
		for _, k in { "score", "distance", "coins", "nearMisses", "bestCombo" } do
			local v = tonumber(stats[k]) or 0
			if v ~= v or v == math.huge or v < 0 then v = 0 end
			out[k] = v
		end
		return out
	end

	local function onDown(m, st, stats)
		if not st.alive or m.over then return end
		st.alive = false
		st.stats = sanitizeStats(stats) or st.stats
		st.respawnAt = now() + MP.RespawnBase + MP.RespawnStep * st.respawns
		fireMatch(m, "down", { userId = st.userId, respawnAt = st.respawnAt })
		if aliveCount(m) == 0 then
			endMatch(m, "wipe")
		end
	end

	Action.OnServerEvent:Connect(function(player, kind, payload)
		local m = matchOf[player]
		if not m or m.over then return end
		local st = m.players[player]
		if type(payload) == "table" and type(payload.bot) == "number" then
			local b = findSt(m, payload.bot)
			if not b or not b.bot or b.controller ~= player then return end
			st = b
		end
		if kind == "stats" then
			local s = sanitizeStats(payload)
			if s and st.alive then st.stats = s end
		elseif kind == "caught" then
			onDown(m, st, payload)
		elseif kind == "shove" and type(payload) == "table" then
			local target = findSt(m, payload.target)
			local dir = payload.dir == -1 and -1 or 1
			if not target or target == st or not target.alive or not st.alive then return end
			if now() - st.lastShove < 0.6 then return end
			local a, b = st.lastState, target.lastState
			if not a or not b or math.abs(a.z - b.z) > 6 or math.abs(a.x - b.x) > 11 then return end
			st.lastShove = now()
			if target.bot then
				Event:FireClient(target.controller, "shoved", { by = st.userId, name = st.name, dir = dir, bot = target.userId })
			else
				Event:FireClient(target.player, "shoved", { by = st.userId, name = st.name, dir = dir })
			end
		end
	end)

	State.OnServerEvent:Connect(function(player, s)
		local m = matchOf[player]
		if not m or type(s) ~= "table" then return end
		local maxZ = math.max(0, now() - m.startAt) * Config.MaxSpeed * 1.6 + 150
		local function apply(target, v)
			local z, x, y = tonumber(v.z), tonumber(v.x), tonumber(v.y)
			if not z or not x or not y or z ~= z then return end
			-- nobody can be further than the fastest possible run so far
			target.lastState = {
				z = math.min(z, maxZ),
				x = math.clamp(x, -20, 20),
				y = math.clamp(y, -5, 30),
				l = math.clamp(math.floor(tonumber(v.l) or 3), 1, 5),
				p = math.floor(tonumber(v.p) or 1),
				t = now(),
			}
		end
		if s.z then apply(m.players[player], s) end
		if type(s.bots) == "table" then
			for id, v in s.bots do
				local b = findSt(m, tonumber(id))
				if b and b.bot and b.controller == player and type(v) == "table" then apply(b, v) end
			end
		end
	end)

	-- 15 Hz: relay positions, run respawn timers
	task.spawn(function()
		while true do
			task.wait(1 / 15)
			for _, m in matches do
				if m.over then continue end
				local t = now()
				for _, st in m.list do
					if not st.alive and not st.gone and st.respawnAt and t >= st.respawnAt then
						-- back in, next to whoever is furthest ahead
						local leader
						for _, o in m.list do
							if o.alive and not o.gone and o.lastState and (not leader or o.lastState.z > leader.lastState.z) then
								leader = o
							end
						end
						if leader then
							st.alive = true
							st.respawns += 1
							st.respawnAt = nil
							st.lastState = table.clone(leader.lastState)
							fireMatch(m, "respawn", { userId = st.userId, z = leader.lastState.z, lane = leader.lastState.l })
						end
					end
				end
				local pack = {}
				for _, st in m.list do
					if st.lastState and not st.gone then
						local ls = st.lastState
						pack[tostring(st.userId)] = { z = ls.z, x = ls.x, y = ls.y, l = ls.l, p = st.alive and ls.p or 5, t = ls.t }
					end
				end
				for _, st in m.list do
					if not st.bot and not st.gone and st.player.Parent then
						State:FireClient(st.player, pack)
					end
				end
			end
		end
	end)

	---------------------------------------------------------------------------
	-- QUEUE: local grouping first, then cross-server in the live game
	---------------------------------------------------------------------------
	local function groupAndStart(ranked)
		local entries = {}
		for p, q in queue do
			if q.ranked == ranked and not matchOf[p] and p.Parent then
				table.insert(entries, { p = p, q = q, elo = eloOf(p) })
			end
		end
		table.sort(entries, function(a, b) return a.elo < b.elo end)
		local used = {}
		local t = now()
		for i, e in entries do
			if used[e.p] then continue end
			local group = { e }
			local window = 150 + 25 * (t - e.q.t0)
			for j = i + 1, #entries do
				local o = entries[j]
				if #group < MP.MaxPlayers and not used[o.p] and math.abs(o.elo - e.elo) <= window then
					table.insert(group, o)
				end
			end
			local oldest = 0
			for _, g in group do oldest = math.max(oldest, t - g.q.t0) end
			local full = #group >= MP.MaxPlayers
			local ready = full
				or (ranked and #group >= 2 and oldest >= (IS_STUDIO and 2 or 8))
				-- unranked: after a short wait, empty slots are filled with bots
				or (not ranked and oldest >= (MP.BotFillAfter or 10))
			if ready then
				local players = {}
				for _, g in group do
					used[g.p] = true
					table.insert(players, g.p)
				end
				startMatch(players, ranked, nil, (not ranked) and (MP.MaxPlayers - #players) or 0)
			end
		end
	end

	local function teleportToMatch(players, accessCode, match)
		local opts = Instance.new("TeleportOptions")
		opts.ReservedServerAccessCode = accessCode
		opts:SetTeleportData({ match = match })
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, players, opts)
		if not ok then
			warn("[Matchmaking] teleport failed:", err)
			for _, p in players do
				Event:FireClient(p, "toast", "couldn't join the match, try again")
			end
		end
	end

	if crossServer then
		pcall(function()
			MessagingService:SubscribeAsync("SmiskiMatchFound", function(msg)
				local d = msg.Data
				if type(d) ~= "table" or type(d.userIds) ~= "table" then return end
				local mine = {}
				for _, uid in d.userIds do
					local p = Players:GetPlayerByUserId(uid)
					if p and queue[p] then
						queue[p] = nil
						table.insert(mine, p)
					end
				end
				if #mine > 0 then
					teleportToMatch(mine, d.accessCode, { ranked = d.ranked, seed = d.seed, userIds = d.userIds })
				end
			end)
		end)

		-- publish local players who've waited a bit, and try to form matches with other servers
		task.spawn(function()
			while true do
				task.wait(3)
				local t = now()
				for p, q in queue do
					if t - q.t0 > 4 and (not q.published or t - q.published > 20) then
						local ok = pcall(queueMap.SetAsync, queueMap, tostring(p.UserId), { u = p.UserId, e = eloOf(p), r = q.ranked, j = game.JobId, t = q.t0 }, 90)
						if ok then q.published = t end
					end
				end
				if next(queue) == nil then continue end
				local ok, items = pcall(queueMap.GetRangeAsync, queueMap, Enum.SortDirection.Ascending, 60)
				if not ok or not items then continue end
				for _, ranked in { false, true } do
					local pool = {}
					for _, it in items do
						local v = it.value
						if type(v) == "table" and v.r == ranked and not v.c then table.insert(pool, v) end
					end
					table.sort(pool, function(a, b) return a.e < b.e end)
					-- anchor on one of our own players so each server only forms its share
					for _, anchor in pool do
						if anchor.j ~= game.JobId then continue end
						local group = { anchor }
						local window = 150 + 25 * (t - anchor.t)
						for _, o in pool do
							if o ~= anchor and #group < MP.MaxPlayers and math.abs(o.e - anchor.e) <= window then
								table.insert(group, o)
							end
						end
						local crossesServers = false
						for _, g in group do
							if g.j ~= game.JobId then crossesServers = true end
						end
						if #group < 2 or not crossesServers then continue end
						-- claim everyone atomically-ish; back out if anyone was taken
						local claim = HttpService:GenerateGUID(false)
						local claimed = {}
						for _, g in group do
							local okc, v = pcall(queueMap.UpdateAsync, queueMap, tostring(g.u), function(old)
								if type(old) ~= "table" or old.c then return nil end
								old.c = claim
								return old
							end, 60)
							if okc and type(v) == "table" and v.c == claim then
								table.insert(claimed, g)
							else
								break
							end
						end
						if #claimed == #group then
							local okr, code = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
							if okr then
								local ids = {}
								for _, g in group do table.insert(ids, g.u) end
								pcall(MessagingService.PublishAsync, MessagingService, "SmiskiMatchFound", { accessCode = code, userIds = ids, ranked = ranked, seed = math.random(1, 2 ^ 30) })
								for _, g in group do pcall(queueMap.RemoveAsync, queueMap, tostring(g.u)) end
							end
						else
							for _, g in claimed do
								pcall(queueMap.UpdateAsync, queueMap, tostring(g.u), function(old)
									if type(old) == "table" and old.c == claim then old.c = nil return old end
									return nil
								end, 60)
							end
						end
						break
					end
				end
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			groupAndStart(false)
			groupAndStart(true)
			for p, q in queue do
				Event:FireClient(p, "queueTick", { since = q.t0, ranked = q.ranked })
			end
		end
	end)

	---------------------------------------------------------------------------
	-- RESERVED MATCH SERVERS (live game): start when everyone has arrived
	---------------------------------------------------------------------------
	if IS_MATCH_SERVER then
		local pending, firstArrival
		local function tryStart(force)
			if not pending or pending.started then return end
			local present = {}
			for _, uid in pending.userIds do
				local p = Players:GetPlayerByUserId(uid)
				if p and api.sessions[p] then table.insert(present, p) end
			end
			if #present == #pending.userIds or (force and #present > 0) then
				pending.started = true
				startMatch(present, pending.ranked, pending.seed)
			end
		end
		Players.PlayerAdded:Connect(function(p)
			local jd = p:GetJoinData()
			local td = jd and jd.TeleportData
			if type(td) == "table" and type(td.match) == "table" and not pending then
				pending = td.match
			end
			if not firstArrival then
				firstArrival = true
				task.delay(20, function() tryStart(true) end)
			end
			-- wait for their data to load, then check
			for _ = 1, 40 do
				if api.sessions[p] then break end
				task.wait(0.25)
			end
			tryStart(false)
		end)
	else
		-- arrived in someone's lobby server through a friend code
		Players.PlayerAdded:Connect(function(p)
			local jd = p:GetJoinData()
			local td = jd and jd.TeleportData
			if type(td) == "table" and type(td.joinLobby) == "string" then
				for _ = 1, 40 do
					if api.sessions[p] then break end
					task.wait(0.25)
				end
				joinLocalLobby(p, td.joinLobby)
			end
		end)
	end

	---------------------------------------------------------------------------
	-- CLIENT REQUESTS
	---------------------------------------------------------------------------
	local lastReq = {}
	Request.OnServerInvoke = function(player, action, arg)
		local t = os.clock()
		lastReq[player] = lastReq[player] or {}
		local key = tostring(action)
		if lastReq[player][key] and t - lastReq[player][key] < 0.25 then return { ok = false, reason = "slow down" } end
		lastReq[player][key] = t
		if action == "leaveMatch" then
			if leaveMatchRef then leaveMatchRef(player) end
			sendStatus(player)
			return { ok = true }
		end
		if matchOf[player] and action ~= "status" then
			return { ok = false, reason = "you're in a match" }
		end

		if action == "status" then
			sendStatus(player)
			return { ok = true }
		elseif action == "createLobby" then
			leaveQueue(player)
			leaveLobby(player)
			local code = newCode()
			lobbies[code] = { code = code, host = player, members = { player } }
			lobbyOf[player] = code
			if lobbyMap and not IS_STUDIO then
				task.spawn(pcall, lobbyMap.SetAsync, lobbyMap, code, { j = game.JobId }, 3 * 3600)
			end
			sendStatus(player)
			return { ok = true, code = code }
		elseif action == "joinLobby" then
			local code = type(arg) == "string" and arg:upper():gsub("[^%w]", ""):sub(1, 5) or ""
			if #code ~= 5 then return { ok = false, reason = "codes are 5 letters" } end
			if lobbies[code] then
				local ok, reason = joinLocalLobby(player, code)
				return { ok = ok, reason = reason }
			end
			-- lobby lives in another server: follow it there
			if lobbyMap and not IS_STUDIO then
				local ok, v = pcall(lobbyMap.GetAsync, lobbyMap, code)
				if ok and type(v) == "table" and v.j and v.j ~= game.JobId then
					local opts = Instance.new("TeleportOptions")
					opts.ServerInstanceId = v.j
					opts:SetTeleportData({ joinLobby = code })
					local okT, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, opts)
					if okT then return { ok = true, teleporting = true } end
					warn("[Matchmaking] lobby teleport failed:", err)
				end
			end
			return { ok = false, reason = "no lobby with that code" }
		elseif action == "leaveLobby" then
			leaveLobby(player)
			return { ok = true }
		elseif action == "startLobby" then
			local code = lobbyOf[player]
			local l = code and lobbies[code]
			if not l or l.host ~= player then return { ok = false, reason = "only the host can start" } end
			for _, m in l.members do
				if matchOf[m] then return { ok = false, reason = "someone is still in a match" } end
			end
			startMatch(table.clone(l.members), false, nil, arg == false and 0 or (MP.MaxPlayers - #l.members), l.map)
			return { ok = true }
		elseif action == "setLobbyMap" then
			-- the host picks any map THEY own; everyone in the lobby plays it
			local code = lobbyOf[player]
			local l = code and lobbies[code]
			if not l or l.host ~= player then return { ok = false, reason = "only the host picks the map" } end
			local mapDef = type(arg) == "string" and Config.Map(arg)
			if not mapDef or mapDef.id ~= arg then return { ok = false } end
			local s = api.sessions[player]
			if not (mapDef.free or (s and s.data.OwnedMaps and s.data.OwnedMaps[arg])) then
				return { ok = false, reason = "you don't own that map yet" }
			end
			l.map = arg
			pushLobby(l)
			return { ok = true }
		elseif action == "browse" then
			-- what's going on at this table: open lobbies + runs you can hop into
			local out = { lobbies = {}, runs = {}, queued = 0 }
			for _, l in lobbies do
				table.insert(out.lobbies, { code = l.code, host = l.host.DisplayName, n = #l.members, max = MP.MaxPlayers })
			end
			for _, q in queue do if not q.ranked then out.queued += 1 end end
			local t = now()
			for id, m in matches do
				if not m.over then
					local names, bots, live, lead = {}, 0, 0, 0
					for _, st in m.list do
						if not st.gone then
							live += 1
							if st.bot then bots += 1 else table.insert(names, st.name) end
							if st.lastState then lead = math.max(lead, st.lastState.z) end
						end
					end
					table.insert(out.runs, {
						id = id, names = names, bots = bots, ranked = m.ranked, map = Config.Map(m.map or "house").name,
						secs = math.max(0, math.floor(t - m.startAt)), leadM = math.floor(lead / Config.StudsPerMeter),
						joinable = not m.ranked and (bots > 0 or live < MP.MaxPlayers),
					})
				end
			end
			return { ok = true, data = out }
		elseif action == "joinRun" then
			local m = type(arg) == "string" and matches[arg]
			if not m or m.over then return { ok = false, reason = "that run just ended" } end
			if m.ranked then return { ok = false, reason = "ranked runs are locked" } end
			local live, bot = 0, nil
			for _, st in m.list do
				if not st.gone then
					live += 1
					if st.bot and not bot then bot = st end
				end
			end
			if not bot and live >= MP.MaxPlayers then return { ok = false, reason = "that run is full" } end
			leaveQueue(player)
			leaveLobby(player)
			-- a bot steps aside for the real player
			if bot then
				bot.gone = true
				bot.alive = false
				fireMatch(m, "left", { userId = bot.userId })
			end
			local info = playerInfo(player)
			info.lane = 3
			local st = {
				player = player, userId = player.UserId, name = player.DisplayName, lane = 3,
				alive = false, gone = false, respawns = 0,
				respawnAt = now() + 2.5, -- the respawn loop drops them in next to the leader
				stats = { score = 0, distance = 0, coins = 0, nearMisses = 0, bestCombo = 1 },
				elo = info.elo, lastShove = 0,
			}
			fireMatch(m, "joined", info)
			m.players[player] = st
			table.insert(m.list, st)
			matchOf[player] = m
			table.insert(m.infos, info)
			local players = {}
			for _, i in m.infos do
				local o = findSt(m, i.userId)
				if o and not o.gone then table.insert(players, i) end
			end
			Event:FireClient(player, "matchStart", { id = m.id, seed = m.seed, startAt = m.startAt, ranked = false, players = players, joining = true, respawnAt = st.respawnAt, map = m.map })
			if api.feed then api.feed(player.DisplayName .. " jumped into a squad run", "squad") end
			sendStatus(player)
			return { ok = true }
		elseif action == "botMatch" then
			leaveQueue(player)
			leaveLobby(player)
			startMatch({ player }, false, nil, MP.MaxPlayers - 1)
			return { ok = true }
		elseif action == "queue" then
			leaveLobby(player)
			queue[player] = { ranked = arg == true, t0 = now() }
			sendStatus(player)
			return { ok = true }
		elseif action == "cancelQueue" then
			leaveQueue(player)
			sendStatus(player)
			return { ok = true }
		elseif action == "returnToLobby" then
			if IS_MATCH_SERVER then
				pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player })
			end
			return { ok = true }
		end
		return { ok = false }
	end

	-- walk away from a match (MENU button) or disconnect: same bookkeeping
	local function leaveMatch(player)
		local m = matchOf[player]
		if m then
			local st = m.players[player]
			st.gone = true
			st.alive = false
			matchOf[player] = nil
			fireMatch(m, "left", { userId = st.userId })
			local humans = 0
			for _, o in m.list do
				if o.bot and o.controller == player then
					o.gone = true
					o.alive = false
					fireMatch(m, "left", { userId = o.userId })
				elseif not o.bot and not o.gone then
					humans += 1
				end
			end
			if humans == 0 or aliveCount(m) == 0 then endMatch(m, "wipe") end
		end
	end
	leaveMatchRef = leaveMatch
	Players.PlayerRemoving:Connect(function(player)
		leaveQueue(player)
		leaveLobby(player)
		lastReq[player] = nil
		leaveMatch(player)
	end)

	return {
		startMatch = startMatch,
		matches = matches,
	}
end
