-- CityKitchen (client): the restaurant framework, and the pizzeria that is
-- the first kitchen built on it.
--
-- A RESTAURANT IS DATA, NOT CODE. Config.Restaurants holds the menu, the
-- toppings and the `steps` pipeline; this module knows how to play each KIND
-- of step, not what any particular kitchen makes. Adding the bakery means
-- adding a Config entry whose steps say "mix / shape / prove / bake /
-- decorate" -- only a genuinely new kind of minigame needs code here.
--
-- FIVE KINDS OF STEP, all one tap or one hold, because this has to work on a
-- phone with a thumb:
--   stop   a marker sweeps a bar, stop it in the middle      (stretch dough)
--   fill   hold to pour, let go inside the band              (spread sauce)
--   pick   tap what the ticket asks for off a tray           (toppings)
--   bake   a timer with a good window, pull it at the right moment
--   taps   tap in time with a sweeping line, N times         (cut it)
--   serve  no minigame: carry it to the customer
--
-- AND THE STATIONS ARE APART ON PURPOSE. The pipeline walks you down the left
-- wall, along the back and out to the pass, so an order is a lap of the room.
-- A kitchen you could work standing still would be a menu with a floor under
-- it, and the whole point of the job is that you are IN the city.
--   deps: K, UI, Audio, Places, Config, Models, City, Jobs, S, player
return function(deps)
	local K, UI, Audio, Places, Config = deps.K, deps.UI, deps.Audio, deps.Places, deps.Config
	local Models, City, Jobs, S, player = deps.Models, deps.City, deps.Jobs, deps.S, deps.player
	local V, rgb = K.V, K.rgb
	local C = UI.C
	local CITY = Places.CITY

	local Kit = { order = nil, venue = nil }
	local function flat(v) return V(v.X, 0, v.Z) end

	-- the workplace you are standing in, if it is one with stations
	local function workplaceAt(me)
		for _, v in (deps.Build.venues or {}) do
			if v.work and (flat(me) - flat(v.pos)).Magnitude < 34 then return v end
		end
		return nil
	end
	Kit.at = workplaceAt

	local function station(v, id)
		for _, st in v.stations do
			if st.id == id then return st end
		end
		return nil
	end

	---------------------------------------------------------------------------
	-- THE CUSTOMER. Somebody has to be waiting, or the ticket is homework.
	---------------------------------------------------------------------------
	local cust
	local function clearCustomer()
		if cust then cust.rig.model:Destroy() cust = nil end
	end
	local function spawnCustomer(v, ticket)
		clearCustomer()
		local def = Config.Characters[math.random(1, #Config.Characters)]
		local rig = Models.buildSminski(K.actors, 1, def, false, nil)
		local at = CFrame.new(CITY + v.queue) * CFrame.Angles(0, math.atan2(
			(v.counter - v.queue).X, (v.counter - v.queue).Z), 0)
		Models.poseSminski(rig, at, "idle", math.random() * 10)
		-- the ticket, over their head, so you can read the order from anywhere
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(190, 76)
		bb.StudsOffset = Vector3.new(0, 5.4, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		bb.Adornee = rig.body
		bb.Parent = rig.body
		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = C.paper
		card.BorderSizePixel = 0
		card.Parent = bb
		local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0, 12) cc.Parent = card
		UI.text(card, string.upper(ticket.name), { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 6),
			Font = Enum.Font.FredokaOne, TextSize = 19 })
		UI.text(card, ticket.note, { Size = UDim2.new(1, -12, 0, 38), Position = UDim2.fromOffset(6, 30),
			TextSize = 13, TextColor3 = C.inkSoft, TextWrapped = true })
		cust = { rig = rig, bb = bb }
		Audio.play("Chime", 1.3, 0.5)
	end

	---------------------------------------------------------------------------
	-- A TICKET. What this customer wants, and how to say it in one line.
	---------------------------------------------------------------------------
	local function rollTicket(R)
		local m = R.menu[math.random(1, #R.menu)]
		local pool = {}
		for _, t in R.toppings do table.insert(pool, t) end
		local want = {}
		for _ = 1, math.min(m.n, #pool) do
			table.insert(want, table.remove(pool, math.random(1, #pool)))
		end
		local names = {}
		for _, t in want do table.insert(names, t.name) end
		return {
			id = m.id, name = m.name, pay = m.pay, want = want,
			note = #names > 0 and table.concat(names, ", ") or "just as it comes",
		}
	end

	---------------------------------------------------------------------------
	-- THE MINIGAME PANEL. One card, reused by every step -- a title, the hint,
	-- a track with a marker on it and one big button under your thumb.
	---------------------------------------------------------------------------
	local panel = {}
	do
		local dim, card = City.modalCard(560, 340, "")
		panel.shade = dim
		panel.title = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 34), Position = UDim2.fromOffset(24, 14),
			Font = Enum.Font.FredokaOne, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left })
		panel.hint = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 22), Position = UDim2.fromOffset(24, 52),
			TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		-- the track
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -48, 0, 40)
		track.Position = UDim2.fromOffset(24, 96)
		track.BackgroundColor3 = C.paper2
		track.BorderSizePixel = 0
		track.Parent = card
		local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 20) tc.Parent = track
		panel.track = track
		panel.band = Instance.new("Frame")
		panel.band.BackgroundColor3 = C.mint
		panel.band.BorderSizePixel = 0
		panel.band.Size = UDim2.fromScale(0.2, 1)
		panel.band.Position = UDim2.fromScale(0.4, 0)
		panel.band.Parent = track
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 20) bc.Parent = panel.band
		panel.mark = Instance.new("Frame")
		panel.mark.AnchorPoint = Vector2.new(0.5, 0)
		panel.mark.Size = UDim2.fromOffset(10, 52)
		panel.mark.Position = UDim2.new(0, 0, 0, -6)
		panel.mark.BackgroundColor3 = C.ink
		panel.mark.BorderSizePixel = 0
		panel.mark.ZIndex = 4
		panel.mark.Parent = track
		local mc = Instance.new("UICorner") mc.CornerRadius = UDim.new(0, 5) mc.Parent = panel.mark
		-- the tray (toppings), hidden unless a step needs it
		panel.tray = Instance.new("Frame")
		panel.tray.BackgroundTransparency = 1
		panel.tray.Size = UDim2.new(1, -48, 0, 92)
		panel.tray.Position = UDim2.fromOffset(24, 92)
		panel.tray.Visible = false
		panel.tray.Parent = card
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(150, 42)
		gl.CellPadding = UDim2.fromOffset(9, 8)
		gl.Parent = panel.tray
		panel.ticket = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 24), Position = UDim2.fromOffset(24, 196),
			Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = C.mintDark,
			TextXAlignment = Enum.TextXAlignment.Left })
		panel.go = UI.button(card, "GO", { size = UDim2.fromOffset(260, 62), pos = UDim2.new(0.5, 0, 1, -18),
			anchor = Vector2.new(0.5, 1), color = C.mint, textSize = 24, onClick = function()
				if panel.onGo then panel.onGo() end
			end })
	end

	local function closePanel()
		panel.shade.Visible = false
		panel.onGo = nil
		panel.step = nil
		panel.tray.Visible = false
		panel.track.Visible = true
		for _, c in panel.tray:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end
	Kit.closePanel = closePanel

	---------------------------------------------------------------------------
	-- THE STEPS
	---------------------------------------------------------------------------
	local function openStep(st, def, finish)
		local o = Kit.order
		panel.title.Text = def.name
		panel.hint.Text = def.hint or ""
		panel.ticket.Text = string.upper(o.ticket.name) .. "  \u{00B7}  " .. o.ticket.note
		panel.tray.Visible = false
		panel.track.Visible = true
		panel.band.BackgroundColor3 = C.mint
		panel.go.setColor(C.mint)
		panel.shade.Visible = true

		if def.kind == "pick" then
			-- tap what the ticket asks for. Wrong ones cost, missing ones cost
			-- more, and the score is what actually landed on the pizza.
			panel.track.Visible = false
			panel.tray.Visible = true
			local R = Config.Restaurant(o.rid)
			local picked = {}
			local want = {}
			for _, t in o.ticket.want do want[t.id] = true end
			local btns = {}
			for _, t in R.toppings do
				local b = UI.button(panel.tray, t.name, { size = UDim2.fromOffset(150, 42), color = t.color,
					textSize = 16, onClick = function()
						picked[t.id] = not picked[t.id] or nil
						btns[t.id].setText(picked[t.id] and ("\u{2713} " .. t.name) or t.name)
						btns[t.id].setColor(picked[t.id] and C.mintDark or t.color)
						Audio.play("Click", picked[t.id] and 1.3 or 0.9, 0.4)
					end })
				btns[t.id] = b
			end
			panel.go.setText("THAT'S EVERYTHING")
			panel.kind, panel.btns, panel.want = "pick", btns, want
			panel.onGo = function()
				local hit, miss, extra = 0, 0, 0
				for id in want do
					if picked[id] then hit += 1 else miss += 1 end
				end
				for id in picked do
					if not want[id] then extra += 1 end
				end
				local total = math.max(1, hit + miss)
				finish(math.clamp((hit - extra * 0.7) / total, 0, 1))
			end
			return
		end

		if def.kind == "serve" then
			panel.track.Visible = false
			panel.go.setText("HAND IT OVER")
			panel.hint.Text = "one " .. string.lower(o.ticket.name) .. ", ready to go"
			panel.kind = "serve"
			panel.onGo = function() finish(1) end
			return
		end

		-- everything else is a moving marker with a good window in it
		local band, speed, dir = 0.2, 1.1, 1
		if def.kind == "fill" then
			band, speed, dir = 0.16, 0.55, 1
			panel.mark.Position = UDim2.new(0, 0, 0, -6)
			panel.band.Size = UDim2.fromScale(band, 1)
			panel.band.Position = UDim2.fromScale(0.62, 0)
		elseif def.kind == "bake" then
			band, speed = 0.18, 0.42
			panel.band.Size = UDim2.fromScale(band, 1)
			panel.band.Position = UDim2.fromScale(0.58, 0)
			panel.band.BackgroundColor3 = C.gold
		elseif def.kind == "taps" then
			band, speed = 0.22, 1.5
			panel.band.Size = UDim2.fromScale(band, 1)
			panel.band.Position = UDim2.fromScale(0.39, 0)
		else -- stop
			band, speed = 0.18, 1.25
			panel.band.Size = UDim2.fromScale(band, 1)
			panel.band.Position = UDim2.fromScale(0.41, 0)
		end
		local bandLo = panel.band.Position.X.Scale
		local bandHi = bandLo + band
		local x, running = 0, true
		local hits, need = {}, def.taps or 1
		panel.kind, panel.need, panel.lo, panel.hi = def.kind, need, bandLo, bandHi
		panel.pos = function() return x end
		-- a fill or a bake only moves while it is "pouring"/"cooking": the
		-- marker runs on its own and you decide when to stop it. Same input,
		-- one tap, which is the whole reason they share a panel.
		-- THE VERB IS THE STEP'S, NOT ALWAYS "CUT". This panel was written for
		-- the pizzeria, where the taps step is cutting a pizza. The same step
		-- at the bakery is icing and at the burger bar it is wrapping, and a
		-- button reading CUT while you ice a cake is the game describing a
		-- different shop. Defaults to CUT, so the pizzeria is unchanged.
		local verb = def.verb or "CUT"
		panel.go.setText(def.kind == "taps" and (verb .. "  (0/" .. need .. ")") or "NOW")
		local conn
		local function score()
			local total = 0
			for _, h in hits do total += h end
			return #hits > 0 and (total / #hits) or 0
		end
		local function stop(final)
			running = false
			if conn then conn:Disconnect() conn = nil end
			finish(final)
		end
		panel.onGo = function()
			if not running then return end
			local mid = (bandLo + bandHi) / 2
			local off = math.abs(x - mid) / math.max(0.01, band / 2 + 0.34)
			table.insert(hits, math.clamp(1 - off, 0, 1))
			Audio.play("Click", 1 + math.clamp(1 - off, 0, 1) * 0.6, 0.5)
			if #hits >= need then
				stop(score())
			else
				panel.go.setText(verb .. "  (" .. #hits .. "/" .. need .. ")")
			end
		end
		conn = game:GetService("RunService").RenderStepped:Connect(function(dt)
			if not running then return end
			x += dir * speed * dt
			if x > 1 then x, dir = 1, -1 elseif x < 0 then x, dir = 0, 1 end
			panel.mark.Position = UDim2.new(x, 0, 0, -6)
			-- a bake that is left in too long is a burnt one: it ends by itself
			if def.kind == "bake" and x >= 1 and dir == -1 and #hits == 0 then
				stop(0.15)
			end
		end)
		panel.conn = conn
	end

	---------------------------------------------------------------------------
	-- THE ORDER LOOP
	---------------------------------------------------------------------------
	function Kit.newOrder(v)
		local R = Config.Restaurant(v.work)
		if not R then return end
		Kit.venue = v
		local ticket = rollTicket(R)
		Kit.order = { rid = v.work, ticket = ticket, step = 1, scores = {}, t0 = os.clock() }
		spawnCustomer(v, ticket)
		Jobs.notify("heart", "NEW ORDER", ticket.name .. " \u{00B7} " .. ticket.note, R.accent)
	end

	local function finishOrder()
		local o = Kit.order
		local R = Config.Restaurant(o.rid)
		local quality = 0
		for i, st in R.steps do
			quality += (o.scores[i] or 0) * st.weight
		end
		local secs = os.clock() - o.t0
		local speed = math.clamp((R.par or 40) / math.max(1, secs), 0, 1)
		local final = math.clamp(quality * 0.85 + speed * 0.15, 0, 1)
		clearCustomer()
		Kit.order = nil
		closePanel()
		local res = Jobs.task({ item = o.ticket.id, score = final, secs = math.floor(secs) })
		if res and res.ok then
			-- straight into the next one: the queue is the job
			task.delay(1.4, function()
				if Jobs.state and Jobs.state.job == "pizzeria" and Kit.venue then Kit.newOrder(Kit.venue) end
			end)
		end
	end

	local function stepDone(score)
		local o = Kit.order
		if not o then return end
		o.scores[o.step] = score
		closePanel()
		local R = Config.Restaurant(o.rid)
		local pct = math.floor(score * 100)
		UI.popText(R.steps[o.step].name .. "  " .. pct .. "%",
			pct >= 80 and C.mintDark or pct >= 50 and C.gold or C.coral, 24, -60)
		o.step += 1
		if o.step > #R.steps then
			finishOrder()
		else
			local nx = R.steps[o.step]
			Jobs.notify("pin", string.upper(nx.name), "next: the " .. nx.station .. " station", R.accent)
		end
	end

	---------------------------------------------------------------------------
	-- THE PROMPT. What this station offers, given where the ticket is up to.
	---------------------------------------------------------------------------
	function Kit.prompt(me)
		local v = workplaceAt(me)
		if not v then return nil end
		Kit.venue = v
		local R = Config.Restaurant(v.work)
		if not R then return nil end
		local def = Config.Job(R.job)
		local onShift = Jobs.state and Jobs.state.job == R.job
		-- not working here yet: the counter is where you ask for a job
		if not onShift then
			local ct = station(v, "counter")
			if ct and (flat(me) - flat(ct.pos)).Magnitude < 12 then
				return { R.name, "they are short-handed \u{00B7} " .. (def and def.blurb or ""), "WORK HERE", "heart",
					function() Jobs.start(R.job) end, ct.pos }
			end
			return nil
		end
		if not Kit.order then
			local ct = station(v, "counter")
			if ct and (flat(me) - flat(ct.pos)).Magnitude < 14 then
				return { R.name, "an empty counter and a clean oven", "TAKE AN ORDER", "heart",
					function() Kit.newOrder(v) end, ct.pos }
			end
			return { R.name, "head to the pass and take an order", nil, "heart", nil }
		end
		local o = Kit.order
		local want = R.steps[o.step]
		local st = station(v, want.station)
		if not st then return nil end
		local d = (flat(me) - flat(st.pos)).Magnitude
		if d < 11 then
			return { want.name, want.hint or "", "DO IT", "bolt", function()
				openStep(st, want, stepDone)
			end, st.pos }
		end
		-- standing at the wrong bench: say where to go, do not silently do nothing
		for _, other in v.stations do
			if (flat(me) - flat(other.pos)).Magnitude < 11 then
				return { string.upper(other.name), "the ticket says " .. string.lower(want.name) .. " next",
					nil, "pin", nil, other.pos }
			end
		end
		return nil
	end

	-- Studio only. A timing minigame cannot be tested headlessly by firing
	-- blind -- that measures the random number generator, not the game -- so
	-- this plays the current step the way a competent player would: tick
	-- exactly what the ticket asked for, and press when the marker is
	-- actually inside the band.
	function Kit.panelGo()
		if panel.onGo then panel.onGo() end
	end
	function Kit.autoPlay(sloppy)
		if not panel.onGo then return "no step open" end
		if panel.kind == "pick" then
			for id in panel.want do
				if panel.btns[id] and not sloppy then panel.btns[id].press() end
			end
			panel.onGo()
			return "picked"
		end
		if panel.kind == "serve" then panel.onGo() return "served" end
		-- wait for the marker to enter the band, then press; repeat for taps
		local pressed = 0
		local t0 = os.clock()
		while pressed < (panel.need or 1) and os.clock() - t0 < 12 do
			local x = panel.pos and panel.pos() or 0
			local mid = ((panel.lo or 0) + (panel.hi or 1)) / 2
			if math.abs(x - mid) < (sloppy and 0.3 or 0.035) then
				panel.onGo()
				pressed += 1
				task.wait(0.12)
			else
				task.wait()
			end
		end
		return "pressed " .. pressed .. "/" .. tostring(panel.need)
	end

	-- clocking out mid-order abandons it, and takes the customer with it
	function Kit.clear()
		clearCustomer()
		Kit.order = nil
		Kit.playing = nil
		closePanel()
	end

	---------------------------------------------------------------------------
	-- PLAY A SHORT PIPELINE FOR SOMEBODY ELSE. Restaurant Row's SERVE
	-- (CityTycoon) is two of these steps and a hand-over, at the owner's own
	-- pass, with no shift and no Config.Restaurants entry -- so it borrows the
	-- panel rather than the order loop. `ticket` = { name, note }; `steps` =
	-- stop / fill / bake / taps defs (never `pick`: that reads a toppings tray
	-- off Config.Restaurant(o.rid), which a book-recipe does not have).
	-- done(score) gets the weighted mean, or nil if the panel was shut early.
	---------------------------------------------------------------------------
	function Kit.play(ticket, steps, done)
		if Kit.order or Kit.playing then return false end
		Kit.playing = true
		Kit.order = { rid = nil, ticket = { name = ticket.name, note = ticket.note or "", want = {} }, step = 1, scores = {}, t0 = os.clock() }
		local scores = {}
		local i = 0
		local closing = false -- true while the panel is shut BETWEEN steps by us
		local function next_()
			i += 1
			local def = steps[i]
			if not def or def.kind == "pick" then
				local total, wsum = 0, 0
				for k, sc in scores do
					local w = steps[k].weight or 1
					total += sc * w
					wsum += w
				end
				Kit.order = nil
				Kit.playing = nil
				closePanel()
				done(wsum > 0 and math.clamp(total / wsum, 0, 1) or 0)
				return
			end
			closing = false
			openStep(nil, def, function(sc)
				scores[i] = sc
				closing = true
				closePanel()
				local pct = math.floor(sc * 100)
				UI.popText(def.name .. "  " .. pct .. "%", pct >= 80 and C.mintDark or pct >= 50 and C.gold or C.coral, 24, -60)
				task.delay(0.35, next_)
			end)
		end
		-- shutting the card mid-recipe (the X, a tap outside) drops the order,
		-- the way clocking out does. Our own between-step close is not that.
		local conn
		conn = panel.shade:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.shade.Visible or not Kit.playing or closing then return end
			task.defer(function()
				if Kit.playing and not closing and not panel.shade.Visible then
					conn:Disconnect()
					Kit.order = nil
					Kit.playing = nil
					done(nil)
				end
			end)
		end)
		next_()
		return true
	end
	return Kit
end
