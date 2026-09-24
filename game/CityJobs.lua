-- CityJobs (client): the Job Center, the career browser, the shift strip and
-- the notification system every job talks through.
--
-- WHAT THIS MODULE IS, AND IS NOT. It is the paperwork: browsing careers,
-- clocking in and out, showing what a shift has earned, and telling you when
-- something happened. It does not know how any individual job is PLAYED --
-- the pizzeria's stations live in CityKitchen, and taxi/parcels/litter/fields
-- are the city loops City.lua already ran before jobs existed. A job here is
-- one of two things:
--
--   world = <loop>   the job IS the open city, and clocking in just tells the
--                    HUD to count what you were already able to do.
--   room  = <id>     the job happens at stations in a building, and the
--                    matching framework module drives it.
--
-- Keeping that line means adding a career later is a Config entry plus (if it
-- needs one) a framework, not a new copy of any of this.
--   deps: K, UI, Audio, Places, Config, City, S, H, player, remoteNamed
return function(deps)
	local K, UI, Audio, Places, Config = deps.K, deps.UI, deps.Audio, deps.Places, deps.Config
	local City, S, H, player = deps.City, deps.S, deps.H, deps.player
	local remoteNamed = deps.remoteNamed
	local V = K.V
	local C = UI.C
	local CITY = Places.CITY

	local J = { state = nil, cards = {} }

	local function flat(v) return V(v.X, 0, v.Z) end
	local function fmt(n) return UI.fmt and UI.fmt(n) or tostring(n) end

	---------------------------------------------------------------------------
	-- NOTIFICATIONS. One system, every job -- a new fare, a finished order, a
	-- reputation bump all arrive in the same place in the same shape, so a
	-- player learns to read the corner once.
	--
	-- They stack in the bottom-right above the driving buttons, three at most,
	-- and they are SMALL. A job that fires a notification every twenty seconds
	-- cannot be allowed to take the screen; you are supposed to still be
	-- looking at the city.
	---------------------------------------------------------------------------
	local notes = {}
	local noteRoot
	local function noteLayout()
		for i, n in notes do
			UI.tween(n.holder, 0.18, { Position = UDim2.new(1, 0, 1, -(i - 1) * 74) })
		end
	end
	function J.notify(icon, title, sub, color)
		if not noteRoot then return end
		while #notes >= 3 do
			local old = table.remove(notes, 1)
			old.holder:Destroy()
		end
		local holder, card = UI.card(noteRoot, UDim2.fromOffset(320, 66), UDim2.new(1, 0, 1, 40), Vector2.new(1, 1), C.paper)
		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(40, 40)
		badge.Position = UDim2.fromOffset(12, 13)
		badge.BackgroundColor3 = color or C.mint
		badge.Parent = card
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 11) bc.Parent = badge
		UI.icon(badge, icon or "star", { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 4) })
		UI.text(card, title, { Size = UDim2.new(1, -66, 0, 22), Position = UDim2.fromOffset(60, 10),
			Font = Enum.Font.FredokaOne, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		UI.text(card, sub or "", { Size = UDim2.new(1, -66, 0, 18), Position = UDim2.fromOffset(60, 32),
			TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		local n = { holder = holder, until_ = os.clock() + 4.5 }
		table.insert(notes, n)
		noteLayout()
		Audio.play("Click", 1.3, 0.35)
		return n
	end
	function J.stepNotes()
		local now = os.clock()
		for i = #notes, 1, -1 do
			if now > notes[i].until_ then
				notes[i].holder:Destroy()
				table.remove(notes, i)
				noteLayout()
			end
		end
	end

	---------------------------------------------------------------------------
	-- THE SHIFT STRIP. Only on screen while you are clocked in: what you are,
	-- how long you have been at it, what it has paid and how well it is going.
	---------------------------------------------------------------------------
	local strip, sJob, sTime, sPay, sTasks, sScore, sBar
	local function buildHud(root)
		noteRoot = Instance.new("Frame")
		noteRoot.BackgroundTransparency = 1
		noteRoot.AnchorPoint = Vector2.new(1, 1)
		noteRoot.Size = UDim2.fromOffset(340, 240)
		noteRoot.Position = UDim2.new(1, -24, 1, -200)
		noteRoot.Parent = root
		local holder, card = UI.card(root, UDim2.fromOffset(330, 92), UDim2.new(0, 24, 1, -24), Vector2.new(0, 1), C.paper)
		holder.Visible = false
		strip = holder
		sJob = UI.text(card, "", { Size = UDim2.new(1, -110, 0, 24), Position = UDim2.fromOffset(16, 10),
			Font = Enum.Font.FredokaOne, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		sTime = UI.text(card, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(90, 22),
			Position = UDim2.new(1, -16, 0, 11), Font = Enum.Font.FredokaOne, TextSize = 18,
			TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Right })
		sPay = UI.text(card, "", { Size = UDim2.new(1, -120, 0, 26), Position = UDim2.fromOffset(16, 34),
			Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = C.gold,
			TextXAlignment = Enum.TextXAlignment.Left })
		sTasks = UI.text(card, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(120, 20),
			Position = UDim2.new(1, -16, 0, 38), TextSize = 13, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right })
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -32, 0, 8)
		track.Position = UDim2.fromOffset(16, 68)
		track.BackgroundColor3 = C.paper2
		track.BorderSizePixel = 0
		track.Parent = card
		local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 4) tc.Parent = track
		sBar = Instance.new("Frame")
		sBar.Size = UDim2.fromScale(0, 1)
		sBar.BackgroundColor3 = C.mint
		sBar.BorderSizePixel = 0
		sBar.Parent = track
		local fc = Instance.new("UICorner") fc.CornerRadius = UDim.new(0, 4) fc.Parent = sBar
		sScore = UI.text(card, "", { AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(120, 16),
			Position = UDim2.new(1, -16, 1, -2), TextSize = 12, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right })
	end

	function J.refreshHud()
		if not strip then return end
		local st = J.state
		local sh = st and st.shift
		strip.Visible = sh ~= nil
		if not sh then return end
		local def = Config.Job(sh.job)
		sJob.Text = string.upper(st.title or (def and def.name) or sh.job)
		local secs = math.max(0, os.time() + (S.clockOffset or 0) - sh.since)
		sTime.Text = string.format("%d:%02d", secs // 60, secs % 60)
		sPay.Text = fmt(sh.earned) .. " earned"
		sTasks.Text = sh.tasks .. (sh.tasks == 1 and " job done" or " jobs done")
		local sc = (sh.score or 0) / 100
		sBar.Size = UDim2.fromScale(sc, 1)
		sBar.BackgroundColor3 = sc >= 0.85 and C.mintDark or sc >= 0.6 and C.mint or C.gold
		sScore.Text = sh.tasks > 0 and (sh.score .. "% performance") or "first job coming up"
	end

	---------------------------------------------------------------------------
	-- THE CAREER BROWSER. Everything the city has work for, whether or not it
	-- is built yet -- a career you can see and cannot start yet is a goal; a
	-- career that is hidden until it exists is a surprise nobody asked for.
	---------------------------------------------------------------------------
	local browser, rows, eloText, rankText, eloBar, resetBtn, catBtns = {}, {}, nil, nil, nil, nil, {}
	do
		local modalCard = City.modalCard
		local dim, card = modalCard(820, 660, "JOB CENTER")
		browser.shade = dim
		-- your reputation, across the top
		rankText = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 24), Position = UDim2.fromOffset(24, 68),
			Font = Enum.Font.FredokaOne, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left })
		eloText = UI.text(card, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(300, 22),
			Position = UDim2.new(1, -24, 0, 70), TextSize = 14, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right })
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -48, 0, 9)
		track.Position = UDim2.fromOffset(24, 96)
		track.BackgroundColor3 = C.paper2
		track.BorderSizePixel = 0
		track.Parent = card
		local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 5) tc.Parent = track
		eloBar = Instance.new("Frame")
		eloBar.Size = UDim2.fromScale(0, 1)
		eloBar.BackgroundColor3 = C.mint
		eloBar.BorderSizePixel = 0
		eloBar.Parent = track
		local ec = Instance.new("UICorner") ec.CornerRadius = UDim.new(0, 5) ec.Parent = eloBar
		-- category tabs
		local tabRow = Instance.new("Frame")
		tabRow.BackgroundTransparency = 1
		tabRow.Size = UDim2.fromOffset(700, 42)
		tabRow.Position = UDim2.fromOffset(24, 116)
		tabRow.Parent = card
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Padding = UDim.new(0, 8)
		lay.Parent = tabRow
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(1, -48, 1, -240)
		list.Position = UDim2.fromOffset(24, 166)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = C.inkSoft
		list.CanvasSize = UDim2.new()
		list.Parent = card
		browser.list = list

		-- one card per job. Pay, difficulty, where it is and what it wants --
		-- everything you would want before walking across town for it.
		local function jobCard(i, def)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -16, 0, 116)
			row.Position = UDim2.fromOffset(0, (i - 1) * 126)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = list
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 16) cr.Parent = row
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromOffset(56, 56)
			badge.Position = UDim2.fromOffset(16, 16)
			badge.BackgroundColor3 = def.color or C.mint
			badge.Parent = row
			local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 15) bc.Parent = badge
			UI.icon(badge, def.icon or "bag", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 6) })
			UI.text(row, string.upper(def.name), { Size = UDim2.new(1, -240, 0, 26), Position = UDim2.fromOffset(84, 14),
				Font = Enum.Font.FredokaOne, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd })
			UI.text(row, def.blurb or "", { Size = UDim2.new(1, -244, 0, 34), Position = UDim2.fromOffset(84, 38),
				TextSize = 13, TextColor3 = C.inkSoft, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
			-- the facts strip along the bottom
			local stars = string.rep("\u{2605}", def.hard or 1) .. string.rep("\u{2606}", 3 - (def.hard or 1))
			local pay = def.base and (fmt(math.floor(def.base * 0.9)) .. "-" .. fmt(math.floor(def.base * 2.1)) .. " a job") or "-"
			UI.text(row, pay .. "   \u{00B7}   " .. stars .. "   \u{00B7}   " .. (def.place or "")
				.. (def.elo and def.elo > 0 and ("   \u{00B7}   needs " .. def.elo .. " rep") or ""), {
				Size = UDim2.new(1, -244, 0, 20), Position = UDim2.fromOffset(84, 82), TextSize = 13,
				TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			local btn = UI.button(row, "", { size = UDim2.fromOffset(150, 54), pos = UDim2.new(1, -16, 0.5, 0),
				anchor = Vector2.new(1, 0.5), color = def.color or C.mint, textSize = 18, onClick = function()
					local st = J.state
					if st and st.job == def.id then J.quit()
					elseif st and st.job then UI.toast("clock out of " .. (Config.Job(st.job) or {}).name .. " first", C.gold)
					else J.start(def.id) end
				end })
			local done = UI.text(row, "", { AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(180, 16),
				Position = UDim2.new(1, -16, 1, -8), TextSize = 12, TextColor3 = C.inkSoft,
				TextXAlignment = Enum.TextXAlignment.Right })
			return { row = row, btn = btn, def = def, done = done }
		end

		local cat = Config.JobCats[1]
		local function showCat(c)
			cat = c
			for k, b in catBtns do
				b.setColor(k == c and C.mint or C.paper2)
				b.face.TextColor3 = k == c and C.white or C.ink
			end
			for _, r in rows do r.row:Destroy() end
			table.clear(rows)
			local i = 0
			for _, def in Config.Jobs do
				if def.cat == c then
					i += 1
					rows[def.id] = jobCard(i, def)
				end
			end
			list.CanvasSize = UDim2.fromOffset(0, i * 126)
			if J.refreshBrowser then J.refreshBrowser() end
		end
		for i, c in Config.JobCats do
			catBtns[c] = UI.button(tabRow, c, { size = UDim2.fromOffset(c == "FOOD & RETAIL" and 184 or c == "CITY SERVICES" and 172 or 148, 42),
				color = C.paper2, textColor = C.ink, textSize = 15, order = i, onClick = function() showCat(c) end })
		end
		-- a way out of a career you are not enjoying, for the price of a car tyre
		resetBtn = UI.button(card, "", { size = UDim2.fromOffset(300, 50), pos = UDim2.new(0.5, 0, 1, -16),
			anchor = Vector2.new(0.5, 1), color = C.paper2, textColor = C.ink, textSize = 15, onClick = function()
				task.spawn(function()
					local res = remoteNamed("Job", "resetElo")
					if res and res.ok then
						J.setState(res.jobs, res.data)
						UI.toast("reputation reset -- clean slate", C.mintDark)
						Audio.play("BigChime", 1, 0.8)
					elseif res and res.reason then
						UI.toast(res.reason, C.coral)
					end
				end)
			end })
		browser.showCat = showCat
		showCat(cat)
	end

	function J.refreshBrowser()
		local st = J.state
		if not st then return end
		local elo = st.elo or Config.JobEloStart
		rankText.Text = st.rank .. "   \u{00B7}   " .. elo .. " reputation"
		local frac, lo, hi = Config.JobRankProgress(elo)
		eloBar.Size = UDim2.fromScale(frac, 1)
		eloText.Text = st.tasks .. " jobs done  \u{00B7}  " .. fmt(st.earned or 0) .. " earned  \u{00B7}  next rank at " .. hi
		resetBtn.setText("RESET REPUTATION  \u{25C9} " .. fmt(Config.JobEloResetCost))
		for id, r in rows do
			local def = r.def
			local n = (st.done or {})[id] or 0
			local best = (st.best or {})[id]
			r.done.Text = n > 0 and (n .. " done" .. (best and ("  \u{00B7}  best " .. best .. "%") or "")) or ""
			if st.job == id then
				r.btn.setText("CLOCK OUT")
				r.btn.setColor(C.coral)
			elseif def.soon then
				r.btn.setText("NOT OPEN YET")
				r.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
			elseif elo < (def.elo or 0) then
				r.btn.setText("NEEDS " .. def.elo)
				r.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
			else
				r.btn.setText("START WORK")
				r.btn.setColor(def.color or C.mint)
			end
		end
	end

	function J.open()
		browser.shade.Visible = true
		J.refreshBrowser()
		task.spawn(function()
			local res = remoteNamed("Job", "state")
			if res and res.ok then J.setState(res.jobs) end
		end)
	end

	---------------------------------------------------------------------------
	-- CLOCKING IN AND OUT
	---------------------------------------------------------------------------
	function J.setState(st, data)
		if st then J.state = st end
		if data and deps.setData then deps.setData(data) end
		J.refreshHud()
		J.refreshBrowser()
	end

	function J.start(id)
		task.spawn(function()
			local res = remoteNamed("Job", "start", id)
			if not (res and res.ok) then
				UI.toast((res and res.reason) or "could not start that job", C.coral)
				return
			end
			J.setState(res.jobs, res.data)
			local def = Config.Job(id)
			browser.shade.Visible = false
			Audio.play("BigChime", 1, 0.8)
			J.notify("star", "CLOCKED IN", (J.state.title or def.name) .. " \u{00B7} " .. (def.place or ""), def.color)
			if J.onStart then J.onStart(def) end
		end)
	end

	function J.quit(abandon)
		task.spawn(function()
			local res = remoteNamed("Job", "quit", abandon and "abandon" or nil)
			if not (res and res.ok) then return end
			local sum = res.summary
			if J.onQuit then J.onQuit() end
			J.setState(res.jobs, res.data)
			if sum and sum.tasks > 0 then
				J.notify("coin", "SHIFT OVER", sum.tasks .. " jobs \u{00B7} " .. fmt(sum.earned)
					.. " earned \u{00B7} " .. sum.score .. "%", C.gold)
			else
				J.notify("house", "CLOCKED OUT", "see you next shift", C.inkSoft)
			end
		end)
	end

	-- A FINISHED TASK. Every job reports through here, and the server decides
	-- what it was worth -- this only shows the receipt.
	function J.task(payload)
		local res = remoteNamed("Job", "task", payload)
		if not (res and res.ok) then return res end
		J.setState(res.jobs, res.data)
		local bits = { "base " .. fmt(res.base) }
		if res.perf > 0 then table.insert(bits, "+" .. fmt(res.perf) .. " perf") end
		if res.tip > 0 then table.insert(bits, "+" .. fmt(res.tip) .. " tip") end
		if res.streakBonus > 0 then table.insert(bits, "+" .. fmt(res.streakBonus) .. " streak") end
		J.notify("coin", "+" .. fmt(res.coins) .. "  \u{00B7}  " .. res.score .. "%", table.concat(bits, "  "), C.gold)
		if res.eloDelta and res.eloDelta > 0 then
			J.notify("chart", "REPUTATION +" .. res.eloDelta, res.rank .. " \u{00B7} " .. res.elo, C.lav)
		end
		if res.streakBonus > 0 then
			Audio.play("BigChime", 1.1, 0.9)
		else
			Audio.play("Chime", 1.2, 0.7)
		end
		return res
	end

	---------------------------------------------------------------------------
	-- THE BOARD IN THE BUILDING. The browser opens from the HUD too, but only
	-- after you have stood in front of this once -- the building has to matter
	-- (.claude/rules/environment.md: every street earns its place).
	---------------------------------------------------------------------------
	function J.prompt(me)
		local d = (flat(me) - flat(Places.CityJobBoard)).Magnitude
		if d > 14 then return nil end
		local st = J.state
		return { "JOB BOARD", st and (st.rank .. " \u{00B7} " .. st.elo .. " reputation \u{00B7} browse every career in town")
			or "browse every career in town", "BROWSE", "bag", function()
				J.found = true
				J.open()
			end, Places.CityJobBoard }
	end

	function J.init(root)
		buildHud(root)
		-- a world job (a fare, a parcel, a bin, a field) credited a task: the
		-- coins already arrived through that loop, so this only moves the strip
		local ev = game:GetService("ReplicatedStorage"):FindFirstChild("SminskiRemotes")
		ev = ev and ev:FindFirstChild("JobCredited")
		if ev then
			ev.OnClientEvent:Connect(function(st, got, bonus)
				J.setState(st)
				if bonus and bonus > 0 then
					J.notify("coin", "STREAK x" .. (st.streak or 0), "+" .. fmt(bonus) .. " bonus", C.gold)
					Audio.play("BigChime", 1.1, 0.9)
				end
			end)
		end
		task.spawn(function()
			local res = remoteNamed("Job", "state")
			if res and res.ok then J.setState(res.jobs) end
		end)
	end
	return J
end
