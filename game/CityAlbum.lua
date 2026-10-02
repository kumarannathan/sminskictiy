-- CityAlbum: the collection book, the mastery tracks, and the goal widget.
--
-- THREE SCREENS IN ONE MODULE because they answer the same question from
-- different distances. The goal widget is "what now", mastery is "what am I
-- getting good at", the album is "what is left". Splitting them would mean
-- three modules all reading the same two server actions.
--
-- EVERYTHING HERE IS A VIEW. No progress is computed on the client: the
-- server owns what you have and how far along a set is, and this draws the
-- answer. A client that did its own arithmetic would disagree with the thing
-- paying out, and the player would believe the one on screen.
return function(deps)
	local UI, Config, City, remote = deps.UI, deps.Config, deps.City, deps.remote
	local gui = deps.gui
	local C, T = UI.C, UI.T
	local A = {}

	---------------------------------------------------------------------
	-- THE GOAL WIDGET: one line, always something, never empty while work
	-- remains (docs/ONBOARDING.md 5.1). An empty goal widget is the
	-- "what do I do?" problem coming straight back.
	---------------------------------------------------------------------
	local goal, goalText, goalSub, goalFill, goalBtn
	local current   -- the task the widget is showing

	function A.buildGoal(parent)
		local holder, card = UI.card(parent, UDim2.fromOffset(340, 76),
			UDim2.new(0, 24, 1, -120), Vector2.new(0, 1), C.paper)
		holder.Name = "GoalWidget"
		holder.Visible = false
		goal = holder

		UI.icon(card, "star", { Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(10, 10), ZIndex = 3 })
		goalText = UI.text(card, "", { Size = UDim2.new(1, -56, 0, 22),
			Position = UDim2.fromOffset(48, 8), Font = T.font.display,
			TextSize = T.size.md, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		goalSub = UI.text(card, "", { Size = UDim2.new(1, -56, 0, 18),
			Position = UDim2.fromOffset(48, 30), Font = T.font.body,
			TextSize = T.size.xs, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -20, 0, 6)
		track.Position = UDim2.fromOffset(10, 58)
		track.BackgroundColor3 = C.paper3
		track.BorderSizePixel = 0
		track.ZIndex = 3
		track.Parent = card
		goalFill = Instance.new("Frame")
		goalFill.Size = UDim2.fromScale(0, 1)
		goalFill.BackgroundColor3 = C.mint
		goalFill.BorderSizePixel = 0
		goalFill.ZIndex = 4
		goalFill.Parent = track
		return holder
	end

	-- Ask the server what to do next and draw it. Called on join, and after
	-- anything that might have finished a task.
	function A.refreshGoal()
		task.spawn(function()
			local res = remote("task")
			if not res or not res.ok then return end
			current = res.task
			if not goal then return end
			if not current then
				goal.Visible = false
				return
			end
			goal.Visible = true
			goalText.Text = current.text
			goalSub.Text = current.ready and "tap to claim" or (current.how or "")
			local k = current.need > 0 and math.clamp(current.have / current.need, 0, 1) or 0
			goalFill.Size = UDim2.fromScale(k, 1)
			goalFill.BackgroundColor3 = current.ready and C.gold or C.mint
			-- A FINISHED TASK CLAIMS ITSELF rather than waiting to be tapped.
			-- The widget is a signpost, not a chore: making somebody collect
			-- their own reward adds a step that teaches nothing.
			if current.ready then
				task.wait(0.6)
				local c2 = remote("task", "claim", current.id)
				if c2 and c2.ok then
					if c2.coins and c2.coins > 0 then
						City.toast("task done  +" .. c2.coins, C.mintDark)
					end
					A.refreshGoal()
				end
			end
		end)
	end

	function A.trackCurrent() return current and current.track end

	---------------------------------------------------------------------
	-- THE ALBUM
	---------------------------------------------------------------------
	function A.open()
		local holder, card = UI.card(gui, UDim2.fromOffset(660, 440),
			UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.paper)
		holder.Name = "AlbumScreen"

		local title = UI.text(card, "COLLECTION", { Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 12), Font = T.font.display,
			TextSize = T.size.xl, ZIndex = 3 })
		local count = UI.text(card, "", { Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 44), Font = T.font.bold,
			TextSize = T.size.sm, TextColor3 = C.inkSoft, ZIndex = 3 })

		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(1, -24, 1, -150)
		list.Position = UDim2.fromOffset(12, 112)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ZIndex = 3
		list.Parent = card
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, T.space.sm)
		lay.Parent = list

		local tabs = Instance.new("Frame")
		tabs.Size = UDim2.new(1, -24, 0, 40)
		tabs.Position = UDim2.fromOffset(12, 68)
		tabs.BackgroundTransparency = 1
		tabs.ZIndex = 3
		tabs.Parent = card
		local tl = Instance.new("UIListLayout")
		tl.FillDirection = Enum.FillDirection.Horizontal
		tl.Padding = UDim.new(0, T.space.xs)
		tl.Parent = tabs

		local function row(set)
			local f = Instance.new("Frame")
			f.Size = UDim2.new(1, -8, 0, 62)
			f.BackgroundColor3 = C.paper2
			f.BorderSizePixel = 0
			f.ZIndex = 3
			f.Parent = list
			UI.text(f, set.name, { Size = UDim2.new(1, -140, 0, 22),
				Position = UDim2.fromOffset(12, 6), Font = T.font.display,
				TextSize = T.size.md, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
			UI.text(f, set.blurb or "", { Size = UDim2.new(1, -140, 0, 18),
				Position = UDim2.fromOffset(12, 28), Font = T.font.body,
				TextSize = T.size.xs, TextColor3 = C.inkSoft,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
			UI.text(f, ("%d / %d"):format(set.have, set.need), {
				Size = UDim2.fromOffset(80, 24), Position = UDim2.new(1, -92, 0, 8),
				Font = T.font.display, TextSize = T.size.lg,
				TextColor3 = set.done and C.mintDark or C.ink,
				TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
			-- the pips: one per item, so "two to go" is countable at a glance
			-- rather than a percentage you have to translate
			local pips = Instance.new("Frame")
			pips.Size = UDim2.new(1, -24, 0, 8)
			pips.Position = UDim2.fromOffset(12, 48)
			pips.BackgroundTransparency = 1
			pips.ZIndex = 4
			pips.Parent = f
			local pl = Instance.new("UIListLayout")
			pl.FillDirection = Enum.FillDirection.Horizontal
			pl.Padding = UDim.new(0, 3)
			pl.Parent = pips
			for i = 1, set.need do
				local p = Instance.new("Frame")
				p.Size = UDim2.fromOffset(16, 8)
				p.BackgroundColor3 = i <= set.have and C.mint or C.paper3
				p.BorderSizePixel = 0
				p.ZIndex = 5
				p.Parent = pips
			end
			if set.ready then
				UI.button(f, "CLAIM", { size = UDim2.fromOffset(92, 36),
					pos = UDim2.new(1, -100, 1, -8), anchor = Vector2.new(0, 1),
					color = C.gold, textSize = T.size.sm,
					onClick = function()
						task.spawn(function()
							local r = remote("claimSet", set.id)
							if r and r.ok then
								City.toast("set complete" .. (r.title and ("  title: " .. r.title) or ""), C.gold)
								holder:Destroy()
								A.open()
							end
						end)
					end })
			end
			return f
		end

		local function show(page, sets, have, total)
			for _, c in list:GetChildren() do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			for _, set in sets do
				if set.page == page then row(set) end
			end
			count.Text = ("%d / %d collected"):format(have, total)
			list.CanvasSize = UDim2.fromOffset(0, lay.AbsoluteContentSize.Y + 12)
		end

		UI.button(card, "CLOSE", { size = UDim2.fromOffset(140, T.tap.std),
			pos = UDim2.new(0.5, 0, 1, -12), anchor = Vector2.new(0.5, 1),
			color = C.coral, onClick = function() holder:Destroy() end })

		task.spawn(function()
			local res = remote("album")
			if not res or not res.ok then
				count.Text = "could not read your collection"
				return
			end
			for _, pg in Config.AlbumPages do
				local b = Instance.new("Frame")
				b.Size = UDim2.fromOffset(100, 40)
				b.BackgroundTransparency = 1
				b.Parent = tabs
				UI.button(b, pg.name, { size = UDim2.fromOffset(100, 36),
					color = C.paper2, textColor = C.ink, textSize = T.size.xs,
					onClick = function() show(pg.id, res.sets, res.have, res.total) end })
			end
			-- MASTERY IS A TAB OF THE SAME BOOK, not a separate screen. It is
			-- the same question -- what have I got, how far along am I.
			local mb = Instance.new("Frame")
			mb.Size = UDim2.fromOffset(100, 40)
			mb.BackgroundTransparency = 1
			mb.Parent = tabs
			UI.button(mb, "JOBS", { size = UDim2.fromOffset(100, 36),
				color = C.lav, textColor = C.ink, textSize = T.size.xs,
				onClick = function() A.showMastery(list, lay, count) end })
			show(Config.AlbumPages[1].id, res.sets, res.have, res.total)
		end)
		return holder
	end

	---------------------------------------------------------------------
	-- MASTERY TAB
	---------------------------------------------------------------------
	function A.showMastery(list, lay, count)
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		task.spawn(function()
			local res = remote("mastery")
			if not res or not res.ok then return end
			count.Text = res.title and ("title: " .. res.title) or "no title set"
			for _, t in res.tracks do
				local f = Instance.new("Frame")
				f.Size = UDim2.new(1, -8, 0, 62)
				f.BackgroundColor3 = C.paper2
				f.BorderSizePixel = 0
				f.ZIndex = 3
				f.Parent = list
				UI.text(f, ("%s  —  LV %d"):format(t.name, t.level), {
					Size = UDim2.new(1, -120, 0, 22), Position = UDim2.fromOffset(12, 6),
					Font = T.font.display, TextSize = T.size.md,
					TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
				UI.text(f, t.level >= Config.MasteryMax and "mastered"
					or ("%d / %d %s to the next level"):format(t.into, t.need, t.per), {
					Size = UDim2.new(1, -120, 0, 18), Position = UDim2.fromOffset(12, 28),
					Font = T.font.body, TextSize = T.size.xs, TextColor3 = C.inkSoft,
					TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
				local tr = Instance.new("Frame")
				tr.Size = UDim2.new(1, -24, 0, 6)
				tr.Position = UDim2.fromOffset(12, 50)
				tr.BackgroundColor3 = C.paper3
				tr.BorderSizePixel = 0
				tr.ZIndex = 4
				tr.Parent = f
				local fill = Instance.new("Frame")
				fill.Size = UDim2.fromScale(t.need > 0 and math.clamp(t.into / t.need, 0, 1) or 1, 1)
				fill.BackgroundColor3 = C.lav
				fill.BorderSizePixel = 0
				fill.ZIndex = 5
				fill.Parent = tr
				if t.ready then
					UI.button(f, "CLAIM", { size = UDim2.fromOffset(92, 36),
						pos = UDim2.new(1, -12, 0, 10), anchor = Vector2.new(1, 0),
						color = C.gold, textSize = T.size.sm,
						onClick = function()
							task.spawn(function()
								local r = remote("claimMastery", t.id)
								if r and r.ok then
									City.toast(("%s level %d"):format(t.name, r.level)
										.. (r.title and ("  —  " .. r.title) or ""), C.gold)
									A.showMastery(list, lay, count)
								end
							end)
						end })
				end
			end
			list.CanvasSize = UDim2.fromOffset(0, lay.AbsoluteContentSize.Y + 12)
		end)
	end

	return A
end
