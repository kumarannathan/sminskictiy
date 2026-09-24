-- Tour (client): the first-time walkthrough. The camera glides between the
-- places on the table while a caption card explains each one. Skippable,
-- replayable from Settings, and saved on the server once seen.
--   deps: Config, UI, Audio, Places, setCam(cf|nil), onDone()

return function(deps)
	local UI, Audio, Places = deps.UI, deps.Audio, deps.Places
	local C = UI.C
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local HUB = Places.HUB
	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function W(v) return HUB + v end

	local function ent(id)
		local e = Places.entrance(id)
		return e and e.pos or V(0, 0, 0)
	end
	-- a shot framing a diorama from in front of its open side
	local function front(id, dist, height, lookY)
		local e = Places.entrance(id)
		local p = e and e.pos or V(0, 0, 0)
		local f = e and e.face or 0
		local dir = V(math.sin(f), 0, math.cos(f))
		return { pos = W(p + dir * (dist or 44) + V(0, height or 16, 0)), look = W(p + V(0, lookY or 12, 0)) }
	end

	local STOPS = {
		{ shot = { pos = W(V(150, 96, -130)), look = W(V(-60, -8, 60)) },
			title = "WELCOME TO SMINSKI RUN", body = "You're a tiny Sminski living on a side table in someone's bedroom. Everything on this table is a place to go.", icon = "house" },
		{ shot = { pos = W(ent("dollhouse") + V(0, 18, -58)), look = W(ent("dollhouse") + V(0, 11, 0)) },
			title = "ENDLESS RUN", body = "Each hut is a map. Walk through a door to start running: dodge, jump, slide, grab coins and power-ups. Locked huts show their price.", icon = "play" },
		{ shot = front("friends", 42, 18, 10),
			title = "PLAY WITH FRIENDS", body = "The Sminski Cafe: Quick Play finds a squad (bots fill in after 10 seconds), or make a private lobby with a code.", icon = "friends" },
		{ shot = front("arcade", 42, 16, 14),
			title = "RANKED", body = "The Record Shop: race other players for rank. Climb from Glow all the way up.", icon = "trophy" },
		{ shot = { pos = W(ent("dogpark") + V(0, 30, -46)), look = W(ent("dogpark") + V(0, 4, 4)) },
			title = "DOG PARK SURVIVAL", body = "Walk into the fenced pen to queue. Up to 16 Sminskis, giant dogs, flying frisbees. Last one standing wins.", icon = "paw" },
		{ shot = front("store", 44, 16, 14),
			title = "TOY SHOP", body = "Spend coins on outfits and upgrades that make your power-ups last longer. Passes live here too.", icon = "bag" },
		{ shot = front("capsule", 44, 16, 14),
			title = "CAPSULES + COLLECTION", body = "Open capsules to find new Sminskis. Every one has its own passive, like a free shield or bigger coin magnet.", icon = "capsule" },
		{ shot = front("garden", 40, 20, 4),
			title = "SMINSKI GARDEN", body = "Plant seeds, water them once, and come back to harvest. Plants keep growing even while you're away.", icon = "star" },
		{ shot = front("board", 44, 18, 14),
			title = "GOALS", body = "The Library holds your daily and weekly challenges and your stats. Finish goals for bonus coins.", icon = "chart" },
		{ shot = { pos = W(V(Places.HubGateX + 34, 30, -40)), look = W(V(Places.HubGateX, 20, Places.HubGateZ)) },
			title = "SMINSKI CITY", body = "Cross the bridge and walk through the arch in the wall to visit town: drive cars, deliver parcels, sweep the streets and farm. It all pays the same coins.", icon = "house" },
		{ shot = { pos = W(V(-86, 26, -4)), look = W(V(-128, 24, -12)) },
			title = "HALL OF FAME", body = "The all-time leaderboard: longest run and most Dog Park wins, across every server.", icon = "crown" },
	}

	local Tour = { running = false }

	---------------------------------------------------------------------------
	-- UI: letterbox bars + a caption card
	---------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "SminskiTour"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	local barT = Instance.new("Frame")
	barT.BackgroundColor3 = Color3.new(0, 0, 0)
	barT.BorderSizePixel = 0
	barT.Size = UDim2.new(1, 0, 0.09, 0)
	barT.Parent = gui
	local barB = barT:Clone()
	barB.AnchorPoint = Vector2.new(0, 1)
	barB.Position = UDim2.fromScale(0, 1)
	barB.Parent = gui

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local sc = Instance.new("UIScale")
	sc.Parent = root
	local cam = workspace.CurrentCamera
	local function rescale()
		local v = cam.ViewportSize
		local s = math.clamp(math.min(v.X / 1280, v.Y / 760), UIS.TouchEnabled and 0.6 or 0.45, 1.25)
		sc.Scale = s
		root.Size = UDim2.fromOffset(v.X / s, v.Y / s)
	end
	rescale()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local holder, card = UI.card(root, UDim2.fromOffset(660, 178), UDim2.new(0.5, 0, 1, -34), Vector2.new(0.5, 1), C.paper)
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(92, 92)
	badge.Position = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = C.mint
	badge.Parent = card
	local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 22) bc.Parent = badge
	local ic = UI.icon(badge, "house", { Size = UDim2.fromOffset(72, 72), Position = UDim2.fromOffset(10, 10) })
	local title = UI.text(card, "", { Size = UDim2.new(1, -150, 0, 36), Position = UDim2.fromOffset(128, 16), Font = Enum.Font.FredokaOne, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left })
	local body = UI.text(card, "", { Size = UDim2.new(1, -150, 0, 66), Position = UDim2.fromOffset(128, 54), Font = Enum.Font.Gotham, TextSize = 17, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local dots = {}
	for i = 1, #STOPS do
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(9, 9)
		d.Position = UDim2.new(0, 128 + (i - 1) * 15, 1, -30)
		d.BackgroundColor3 = C.paper2
		d.Parent = card
		local dcr = Instance.new("UICorner") dcr.CornerRadius = UDim.new(1, 0) dcr.Parent = d
		dots[i] = d
	end
	local idx, advance, finished = 0, nil, nil
	local nextBtn = UI.button(card, "NEXT", { size = UDim2.fromOffset(150, 52), pos = UDim2.new(1, -18, 1, -14), anchor = Vector2.new(1, 1), color = C.mint, textSize = 22, onClick = function() if advance then advance() end end })
	UI.button(card, "SKIP", { size = UDim2.fromOffset(104, 52), pos = UDim2.new(1, -180, 1, -14), anchor = Vector2.new(1, 1), color = C.paper2, textColor = C.ink, textSize = 20, onClick = function() if finished then finished(true) end end })
	local hint = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(600, 20), Position = UDim2.new(0.5, 0, 1, -222), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.white, stroke = 1 })

	local function showStop(i)
		local s = STOPS[i]
		title.Text = s.title
		body.Text = s.body
		ic.Image = UI.Art.icons[s.icon] or ""
		badge.BackgroundColor3 = ({ C.mint, C.gold, C.sky, C.lav, C.coral })[(i - 1) % 5 + 1]
		for k, d in dots do
			d.BackgroundColor3 = k == i and C.mintDark or k < i and C.mint or C.paper2
			d.Size = k == i and UDim2.fromOffset(20, 9) or UDim2.fromOffset(9, 9)
		end
		nextBtn.setText(i == #STOPS and "LET'S GO!" or "NEXT")
		local ks = holder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", holder)
		local full = math.min(UI.fit(660, 178), UI.compact() and 0.82 or 1)
		ks.Scale = 0.94 * full
		UI.tween(ks, 0.3, { Scale = full }, Enum.EasingStyle.Back)
	end

	-- smooth camera move with ease-in-out and a slow drift while holding
	local function ease(k) return k < 0.5 and 4 * k * k * k or 1 - (-2 * k + 2) ^ 3 / 2 end

	function Tour.run(onDone)
		if Tour.running then return end
		Tour.running = true
		gui.Parent = deps.player and deps.player:FindFirstChild("PlayerGui") or game:GetService("StarterGui")
		gui.Enabled = true
		local kind = UI.inputKind and UI.inputKind() or "keyboard"
		hint.Text = kind == "gamepad" and "A  next   ·   B  skip" or kind == "touch" and "tap NEXT to continue" or "SPACE / ENTER  next   ·   BACKSPACE  skip"
		local from = cam.CFrame
		local moveT, moveDur = 0, 2.2
		local holdT = 0
		local target
		local done = false
		local conns = {}
		finished = function(skipped)
			if done then return end
			done = true
			for _, c in conns do c:Disconnect() end
			Tour.running = false
			gui.Enabled = false
			deps.setCam(nil)
			Audio.play(skipped and "Click" or "BigChime", 1, 0.7)
			if onDone then onDone(skipped) end
		end
		advance = function()
			if done then return end
			if idx >= #STOPS then
				finished(false)
				return
			end
			idx += 1
			from = cam.CFrame
			local s = STOPS[idx].shot
			target = CFrame.lookAt(s.pos, s.look)
			moveT, holdT = 0, 0
			moveDur = idx == 1 and 2.6 or math.clamp((from.Position - s.pos).Magnitude / 110, 1.4, 2.6)
			showStop(idx)
			Audio.play("Whoosh", 0.9 + idx * 0.03, 0.5)
		end
		idx = 0
		advance()
		table.insert(conns, RunService.RenderStepped:Connect(function(dt)
			if done or not target then return end
			moveT = math.min(moveDur, moveT + dt)
			local k = ease(moveT / moveDur)
			local cf = from:Lerp(target, k)
			if moveT >= moveDur then
				-- gentle push-in while the card is up
				holdT += dt
				cf = target * CFrame.new(0, 0, -math.min(holdT, 12) * 0.35)
			end
			deps.setCam(cf)
		end))
		table.insert(conns, UIS.InputBegan:Connect(function(input, gp)
			if gp then return end
			local k = input.KeyCode
			if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.Right then
				advance()
			elseif k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB then
				finished(true)
			end
		end))
	end

	-- something else took over (a match was found, a run started): end quietly
	function Tour.stop()
		if Tour.running and finished then finished(true) end
	end

	return Tour
end
