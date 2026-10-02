-- CityWheel: the prize wheel on the plaza by the Job Center.
--
-- IT IS A REAL OBJECT, NOT A MENU. Walking past it is the reminder that you
-- have a free spin, which is the entire reason it is built out of parts on a
-- lot instead of being another tab in a screen nobody opens.
--
-- THE SERVER DECIDES, THE ANIMATION FOLLOWS. `spin` comes back with the
-- segment index; this module turns the wheel so it lands there. It never
-- picks a result and reports it -- that would make the wheel a suggestion
-- and the payout a formality.
return function(deps)
	local K, UI, Config, Places, City = deps.K, deps.UI, deps.Config, deps.Places, deps.City
	local remote, Audio = deps.remote, deps.Audio
	local C, T = UI.C, UI.T
	local V, rgb = K.V, K.rgb
	local W = {}

	local wheel, face, pointerCF, built, spinning
	local SEGS = #Config.Wheel

	function W.build()
		if built then return built end
		-- PLACES ARE CITY-LOCAL, NOT WORLD. cityPos() on the server subtracts
		-- Places.CITY before comparing, so every Places.X is an offset from
		-- the city origin. Building at the raw value put the wheel thousands
		-- of studs from where the server expects you to stand: the prompt
		-- never appeared and the spin always refused with "it is on the
		-- plaza" while the player was standing on the plaza.
		local base = Places.CITY + Places.CityWheel
		local m = Instance.new("Model")
		m.Name = "PrizeWheel"
		local keep = K.cur
		K.cur = m
		local P = K.P

		-- plinth
		P(V(10, 1, 10), CFrame.new(base + V(0, 0.5, 0)), C.paper3)
		P(V(3, 7, 3), CFrame.new(base + V(0, 4.5, 0)), rgb(120, 86, 60))

		-- THE DISC. One part per segment, laid out as wedges by rotating a
		-- thin slab about the hub. Flat colour rather than a texture, because
		-- a texture would need a 7-way atlas that has to be re-made whenever
		-- the prize table changes -- and the table is meant to be tuned.
		wheel = Instance.new("Part")
		wheel.Size = V(0.6, 14, 14)
		wheel.CFrame = CFrame.new(base + V(0, 11, 0)) * CFrame.Angles(0, math.rad(90), 0)
		wheel.Anchored = true
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Color = C.paper
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.Parent = m

		for i, seg in Config.Wheel do
			local a = (i - 1) / SEGS * math.pi * 2
			local wedge = Instance.new("Part")
			wedge.Size = V(0.8, 6.4, 1.6)
			wedge.Anchored = true
			wedge.CanCollide = false
			wedge.Color = seg.color
			wedge.Material = Enum.Material.SmoothPlastic
			wedge.CFrame = wheel.CFrame * CFrame.Angles(a, 0, 0) * CFrame.new(0.1, 3.6, 0)
			wedge.Parent = wheel
			-- weld so the whole disc turns as one when we tween the hub
			local wj = Instance.new("WeldConstraint")
			wj.Part0, wj.Part1 = wheel, wedge
			wj.Parent = wedge
		end

		-- the pointer at the top: what the wheel lands against
		local pin = P(V(1, 2, 1), CFrame.new(base + V(0, 19, 0)), C.coral)
		pin.Shape = Enum.PartType.Block
		pointerCF = pin.CFrame

		-- the sign, so it reads as a wheel before you are close enough to
		-- get a prompt
		local sign = P(V(12, 2.4, 0.4), CFrame.new(base + V(0, 21.5, 0)), C.lav)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(400, 80)
		sg.Parent = sign
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.FredokaOne
		tl.TextScaled = true
		tl.TextColor3 = C.white
		tl.Text = "DAILY SPIN"
		tl.Parent = sg

		K.cur = keep
		m.Parent = K.actors
		built = m
		return m
	end

	-- WHERE A SEGMENT SITS, as a rotation. Segment 1 is at the top under the
	-- pointer, so landing on `index` means turning back by its share of the
	-- circle, plus whole turns for the show.
	local function angleFor(index, turns)
		return -((index - 1) / SEGS) * math.pi * 2 - (turns or 4) * math.pi * 2
	end

	function W.spin()
		if spinning or not wheel then return end
		spinning = true
		task.spawn(function()
			local res = remote("spin")
			if not res or not res.ok then
				spinning = false
				if res and res.reason then City.toast(res.reason) end
				return
			end
			local TS = game:GetService("TweenService")
			local goal = wheel.CFrame * CFrame.Angles(angleFor(res.index, 5), 0, 0)
			-- a long ease-out is the whole drama of a wheel; Quint rather
			-- than Quad because the slow last half-second is the bit that
			-- makes people lean in
			local tw = TS:Create(wheel, TweenInfo.new(4.2, Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out), { CFrame = goal })
			tw:Play()
			if Audio then Audio.play("Click", 1, 0.4) end
			tw.Completed:Wait()
			local msg = res.name
			if res.furniture then
				local f = Config.Furn(res.furniture)
				msg = (f and f.name or "furniture") .. " for your flat!"
			elseif res.insteadCoins then
				msg = "you own every piece -- have " .. res.insteadCoins .. " coins"
			elseif res.ticket then
				msg = res.name .. "  +1 capsule"
			end
			City.toast(msg, C.gold)
			if Audio then Audio.play("Coin", 1.2, 0.6) end
			spinning = false
		end)
	end

	-- the prompt the city shows when you stand near it
	-- `pos` IS ALREADY CITY-LOCAL. City's loop computes `me` as
	-- hrp.Position - CITY before calling any prompt, so comparing it straight
	-- against a Places value is correct and subtracting CITY again here would
	-- put the test an entire city away. (I briefly "fixed" this the wrong way
	-- after the build bug below, which shared a cause but not a direction.)
	function W.prompt(pos)
		if not Places.CityWheel then return nil end
		if (Vector3.new(pos.X, 0, pos.Z) - Places.CityWheel).Magnitude > 26 then return nil end
		return {
			title = "DAILY SPIN",
			sub = "one free spin a day",
			btn = "SPIN",
			icon = "star",
			act = W.spin,
		}
	end

	-- ODDS ON DEMAND. Roblox requires per-outcome odds for any random reward
	-- and docs/RELEASE.md section 0 makes it a release gate, so the wheel can
	-- always show its own table rather than the numbers living only in a doc.
	function W.showOdds()
		local holder, card = UI.card(deps.gui, UDim2.fromOffset(360, 360),
			UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.paper)
		UI.text(card, "WHAT YOU CAN WIN", { Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 14), Font = T.font.display,
			TextSize = T.size.lg, ZIndex = 3 })
		local odds = Config.WheelOdds()
		local y = 56
		for _, o in odds do
			UI.text(card, o.name, { Size = UDim2.new(1, -40, 0, 22),
				Position = UDim2.fromOffset(20, y), Font = T.font.body,
				TextSize = T.size.sm, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
			UI.text(card, ("%.1f%%"):format(o.pct), { Size = UDim2.new(1, -40, 0, 22),
				Position = UDim2.fromOffset(20, y), Font = T.font.bold,
				TextSize = T.size.sm, TextColor3 = C.inkSoft,
				TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
			y += 26
		end
		UI.button(card, "OK", { size = UDim2.fromOffset(120, T.tap.std),
			pos = UDim2.new(0.5, 0, 1, -12), anchor = Vector2.new(0.5, 1),
			color = C.mint, onClick = function() holder:Destroy() end })
		return holder
	end

	return W
end
