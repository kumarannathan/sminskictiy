-- Multiplayer (client): talks to the server's Matchmaking module and draws
-- the other players' Sminskis, interpolated ~120ms in the past for smoothness.

return function(Config, Models)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")

	local MPc = {}
	MPc.handlers = {}

	local folder = RunService:IsRunning() and ReplicatedStorage:WaitForChild("SminskiMP", 15) or nil
	MPc.available = folder ~= nil
	MPc.matchServer = folder ~= nil and folder:GetAttribute("MatchServer") == true

	local Request, Event, Action, State
	if folder then
		Request = folder:WaitForChild("Request")
		Event = folder:WaitForChild("Event")
		Action = folder:WaitForChild("Action")
		State = folder:WaitForChild("State")
	end

	local function serverNow()
		return workspace:GetServerTimeNow()
	end
	MPc.serverNow = serverNow

	function MPc.request(action, arg)
		if not Request then return { ok = false, reason = "multiplayer needs a live server" } end
		local ok, res = pcall(Request.InvokeServer, Request, action, arg)
		if not ok then return { ok = false, reason = "network error" } end
		return res or { ok = false }
	end

	function MPc.action(kind, payload)
		if Action then Action:FireServer(kind, payload) end
	end

	function MPc.sendState(s)
		if State then State:FireServer(s) end
	end

	---------------------------------------------------------------------------
	-- REMOTE PLAYERS
	---------------------------------------------------------------------------
	local POSES = { "run", "jump", "slide", "fall", "down", "glide" }
	MPc.POSE_CODE = { run = 1, jump = 2, slide = 3, fall = 4, surprised = 1, down = 5, glide = 6 }

	local remotes = {} -- userId -> { rig, info, buf, alive, x, y, z, lane, pose }
	MPc.remotes = remotes
	local folderActors

	-- fadeAfter: seconds until the tag fades away (runs); nil = stays (lobby)
	local function nameplate(rig, info, fadeAfter)
		info.name = info.isBot and (info.name .. " (bot)") or info.name
		local tier = Config.RankTier(info.elo or Config.MP.StartElo)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 36)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 200
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(252, 248, 238)
		f.BackgroundTransparency = 0.1
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = tier.color
		st.Parent = f
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextSize = 18
		l.TextColor3 = Color3.fromRGB(58, 62, 50)
		l.Text = info.name
		l.Parent = f
		f.Parent = bb
		bb.Adornee = rig.head
		bb.Parent = rig.head
		if fadeAfter then
			task.delay(fadeAfter, function()
				if not bb.Parent then return end
				local TS = game:GetService("TweenService")
				local ti = TweenInfo.new(0.6)
				TS:Create(f, ti, { BackgroundTransparency = 1 }):Play()
				TS:Create(st, ti, { Transparency = 1 }):Play()
				TS:Create(l, ti, { TextTransparency = 1 }):Play()
				task.wait(0.65)
				bb.Enabled = false
			end)
		end
		return bb
	end
	MPc.nameplate = nameplate

	function MPc.setupMatch(match, parent, myUserId)
		MPc.clear()
		folderActors = parent
		for _, info in match.players do
			-- bots this client simulates are drawn by the runner, not from packets
			if info.userId ~= myUserId and not (info.isBot and info.controller == myUserId) then
				-- name tags are only useful at the start line: gone 5s after GO
				MPc.addRemote(info, math.max(0, (match.startAt or workspace:GetServerTimeNow()) - workspace:GetServerTimeNow()) + 5)
			end
		end
	end

	-- someone joining mid-run (or at the start line)
	function MPc.addRemote(info, fadeAfter)
		if remotes[info.userId] or not folderActors then return end
		local def = Config.Character(info.char)
		local rig = Models.buildSminski(folderActors, 1, def, true, info.outfit ~= "None" and info.outfit or nil)
		Models.addTrail(rig, def.trail)
		nameplate(rig, info, fadeAfter)
		remotes[info.userId] = { rig = rig, info = info, buf = {}, alive = true, x = 0, y = 0, z = 0, lane = info.lane, pose = "run" }
	end

	function MPc.clear()
		for _, r in remotes do
			r.rig.model:Destroy()
		end
		table.clear(remotes)
	end

	function MPc.setAlive(userId, alive)
		local r = remotes[userId]
		if r then r.alive = alive end
	end

	if State then
		State.OnClientEvent:Connect(function(pack)
			for uid, s in pack do
				local r = remotes[tonumber(uid)]
				if r then
					local last = r.buf[#r.buf]
					if not last or s.t > last.t then
						table.insert(r.buf, s)
						if #r.buf > 12 then table.remove(r.buf, 1) end
					end
				end
			end
		end)
	end

	if Event then
		Event.OnClientEvent:Connect(function(kind, data)
			local h = MPc.handlers[kind]
			if h then h(data) end
		end)
	end

	-- place remote rigs. zOffset converts shared (absolute) z into this client's local z
	function MPc.update(t, zOffset, mapFn)
		local renderT = serverNow() - 0.12
		for _, r in remotes do
			local buf = r.buf
			if #buf == 0 then
				r.rig.model.Parent = nil
				continue
			end
			local a, b = buf[1], nil
			for i = #buf, 1, -1 do
				if buf[i].t <= renderT then
					a = buf[i]
					b = buf[i + 1]
					break
				end
			end
			local x, y, z, pose
			if b then
				local k = math.clamp((renderT - a.t) / math.max(1e-3, b.t - a.t), 0, 1)
				x = a.x + (b.x - a.x) * k
				y = a.y + (b.y - a.y) * k
				z = a.z + (b.z - a.z) * k
				pose = POSES[k < 0.5 and a.p or b.p] or "run"
			else
				-- no newer snapshot yet: extrapolate forward a little
				local last = buf[#buf]
				local prev = buf[#buf - 1]
				local vz = prev and (last.z - prev.z) / math.max(1e-3, last.t - prev.t) or 0
				local ahead = math.clamp(renderT - last.t, 0, 0.4)
				x, y, z = last.x, last.y, last.z + vz * ahead
				pose = POSES[last.p] or "run"
			end
			r.x, r.y, r.z = x, y, z - zOffset
			r.lane = buf[#buf].l
			r.pose = pose
			r.alive = pose ~= "down"
			if r.alive then
				r.rig.model.Parent = folderActors
				Models.setGlider(r.rig, pose == "glide")
				local cf = mapFn and mapFn(r.z, x, y) or CFrame.new(x, y, r.z)
				Models.poseSminski(r.rig, cf, pose, t + r.info.userId % 7, { stride = 17 })
			else
				r.rig.model.Parent = nil
			end
		end
	end

	-- positions of the others in this client's local coordinates
	function MPc.others()
		local out = {}
		for uid, r in remotes do
			if #r.buf > 0 then
				table.insert(out, { userId = uid, name = r.info.name, x = r.x, y = r.y, z = r.z, lane = r.lane, alive = r.alive })
			end
		end
		return out
	end

	function MPc.info(userId)
		local r = remotes[userId]
		return r and r.info
	end

	return MPc
end
