-- CityGuide (client): the welcome tour. Six short cards the first time you
-- arrive in Sminski City, each ringing the bit of the screen it is about.
-- It runs BEFORE the find-your-house tutorial in CityHome (that one waits
-- for cs.tour), can be skipped at any step, and can be replayed from the
-- HELP button. The server remembers that you have seen it ("tourDone").
--   deps: UI, Audio, H (City's HUD handles), onDone (tell the server)

return function(deps)
	local UI, Audio, H = deps.UI, deps.Audio, deps.H
	local C = UI.C
	local Guide = { step = nil }

	-- title, body, icon, and (optionally) which HUD element to ring
	local STEPS = {
		{ "WELCOME TO SMINSKI CITY!", "This is your town. Walk it, drive it, work in it, eat in it. Here is the thirty-second tour.", "house", nil },
		{ "EARN COINS", "CITY JOBS lists every way to earn: parcels from the Post Office, taxi fares, tidying up litter, the farm, and businesses you own. Tap its header to fold it away or bring it back.", "coin", "jobs" },
		{ "EVERY DOOR OPENS", "Shopfronts are real rooms. Order and eat in the cafes, try on outfits in the clothes shops, pet the puppies, play the shop piano. Walk in and look for the prompt.", "bag", nil },
		{ "MIND THE ROAD", "Traffic obeys the lights, and drivers brake late. Cross on green -- step out in front of a bus and you WILL be knocked flying.", "bolt", nil },
		{ "GETTING AROUND", "MAP shows the whole town. MY CAR calls your car. The glowing pad by your own front door jumps you to any district.", "pin", "map" },
		{ "THE ARCADE", "The big neon Arcade at the end of Main St is where the endless runs and Dog Park Survival live. Finish one and you are back on the street outside.", "play", nil },
	}

	-- THE CARD
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.62
	dim.ZIndex = 30
	dim.Visible = false
	dim.Active = true -- swallow taps so the world underneath does not get them
	dim.Parent = H.root
	local W, HT = 540, 300
	local holder, card = UI.card(dim, UDim2.fromOffset(W, HT), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.paper)
	holder.ZIndex = 31
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(64, 64)
	badge.Position = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = C.mint
	badge.Parent = card
	local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 22) cr.Parent = badge
	local icon = UI.icon(badge, "house", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(6, 6) })
	local title = UI.text(card, "", { Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(100, 30), Font = Enum.Font.FredokaOne, TextSize = 28, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left })
	local body = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 120), Position = UDim2.fromOffset(24, 100), Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local dots = UI.text(card, "", { Size = UDim2.fromOffset(160, 24), Position = UDim2.new(0.5, -80, 1, -44), Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = C.inkSoft })
	local skip = UI.button(card, "SKIP", { size = UDim2.fromOffset(110, 46), pos = UDim2.new(0, 20, 1, -14), anchor = Vector2.new(0, 1), color = C.paper2, textColor = C.ink, textSize = 18, onClick = function() Guide.finish() end })
	local nextB = UI.button(card, "NEXT", { size = UDim2.fromOffset(150, 46), pos = UDim2.new(1, -20, 1, -14), anchor = Vector2.new(1, 1), color = C.mint, textSize = 20, onClick = function() Guide.next() end })

	-- a gold ring round whatever the current card is talking about
	local ring
	local function mark(target)
		if ring then ring:Destroy() ring = nil end
		if not target then return end
		ring = Instance.new("UIStroke")
		ring.Color = C.gold
		ring.Thickness = 5
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = target
	end

	function Guide.show(n)
		Guide.step = n
		local st = STEPS[n]
		title.Text, body.Text = st[1], st[2]
		icon.Image = UI.Art.icons[st[3]] or ""
		local d = {}
		for i = 1, #STEPS do d[i] = i == n and "●" or "○" end
		dots.Text = table.concat(d, " ")
		nextB.setText(n == #STEPS and "LET'S GO!" or "NEXT")
		skip.holder.Visible = n < #STEPS
		-- the jobs card is folded on phones: open it while we talk about it
		if st[4] == "jobs" and H.setJobsOpen then H.setJobsOpen(true) end
		if n > 1 and STEPS[n - 1][4] == "jobs" and H.compact and H.setJobsOpen then H.setJobsOpen(false) end
		mark(st[4] == "jobs" and H.jobs or st[4] == "map" and H.mapBtn or nil)
		local fit = UI.fit(W, HT)
		scale.Scale = 0.9 * fit
		UI.tween(scale, 0.25, { Scale = fit }, Enum.EasingStyle.Back)
		Audio.play("Chime", 1 + n * 0.06, 0.6)
	end

	function Guide.start()
		if Guide.step then return end
		dim.Visible = true
		Guide.show(1)
	end

	function Guide.next()
		if not Guide.step then return end
		if Guide.step >= #STEPS then Guide.finish() else Guide.show(Guide.step + 1) end
	end

	function Guide.finish()
		if not Guide.step then return end
		Guide.step = nil
		dim.Visible = false
		mark(nil)
		if H.compact and H.setJobsOpen then H.setJobsOpen(false) end
		Audio.play("BigChime", 1.1, 0.7)
		if deps.onDone then deps.onDone() end
	end

	function Guide.active() return Guide.step ~= nil end

	-- FIRST ARRIVAL: the server says whether you have seen it.
	--
	-- But the city is entered while the title screen is still up -- that is
	-- the whole point, the world builds behind the intro -- so the state
	-- arrives long before the player is looking at the game. Starting the
	-- tour then meant it ran, and finished, against a hidden HUD. Hold it
	-- until somebody has actually pressed START GAME.
	function Guide.onState(cs)
		if cs and cs.tour == false and not Guide.offered then
			Guide.offered = true
			Guide.pending = true
			if not Guide.hold then task.delay(1.4, Guide.start) end
		end
	end

	-- the title screen has handed over; run the tour now if one is owed
	function Guide.release()
		Guide.hold = false
		if Guide.pending and not Guide.step then
			Guide.pending = false
			task.delay(1.2, Guide.start)
		end
	end

	return Guide
end
