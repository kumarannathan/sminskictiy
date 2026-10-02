-- CityFurnish: buying furniture and arranging it in your flat.
--
-- WHY THIS IS ITS OWN MODULE. CityHome already owns the shell -- walls, the
-- skyline, going in and out -- and it is 870 lines. Furnishing is a different
-- job with its own UI, its own input mode and its own server calls, and
-- bolting it onto CityHome would have made the one file nobody wants to open.
-- Home builds the room; this fills it.
--
-- THE LOOP. Buy from a catalogue, then place what you own. Those are
-- deliberately two steps: owning is permanent and feeds the album, placing is
-- a decision you can change without losing the sofa.
--
-- EVERYTHING DEGRADES. Every piece is a curated Inventory template
-- (docs/INVENTORY.md) placed by K.place, and K.place returns nil when the
-- template is missing. A place file without the Inventory folder gets a
-- plain coloured block in the right spot at the right size rather than
-- nothing -- same discipline as the rest of the kit.
return function(deps)
	local UI, K, Config, City, remote = deps.UI, deps.K, deps.Config, deps.City, deps.remote
	local gui, ctx = deps.gui, deps.ctx
	local C, T = UI.C, UI.T
	local F = {}

	local room                 -- the Model we parent placed things to
	local roomCF               -- its CFrame, so local coords mean something
	local shown = {}           -- index -> Model, parallel to the save's array
	local ghost                -- the preview while placing
	local placing              -- { id, r } or nil
	local data                 -- last city payload we were handed

	---------------------------------------------------------------------
	-- RENDERING
	---------------------------------------------------------------------
	-- A placement is room-LOCAL. The interior is rebuilt at a different world
	-- frame every time it streams in, so anything saved in world coordinates
	-- would drift out of the building. local -> world happens here and
	-- nowhere else.
	local function worldOf(p)
		return roomCF * CFrame.new(p.x, 0, p.z) * CFrame.Angles(0, math.rad(p.r or 0), 0)
	end

	local function fallback(def, cf)
		-- NO TEMPLATE: a block of roughly the right size, in a colour that
		-- says "something goes here" rather than pretending to be furniture.
		local part = Instance.new("Part")
		part.Size = Vector3.new(4, 3, 4)
		part.CFrame = cf * CFrame.new(0, 1.5, 0)
		part.Anchored = true
		part.CanCollide = false
		part.Color = C.paper3
		part.Material = Enum.Material.SmoothPlastic
		local m = Instance.new("Model")
		part.Parent = m
		m.PrimaryPart = part
		return m
	end

	local function draw(i, p)
		if shown[i] then shown[i]:Destroy() end
		local def = Config.Furn(p.id)
		local it = def or (Config.SeasonItem(p.id))
		if not it then return end
		local cf = worldOf(p)
		local m = K.place(it.inv, cf) or fallback(it, cf)
		m.Name = "Furn_" .. p.id
		-- GLOW IS A MATERIAL, NOT A LIGHT. performance.md keeps dynamic
		-- lights intentional and limited; a flat with six lamps in it would
		-- otherwise be six lights nobody asked for.
		if it.glow then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then d.Material = Enum.Material.Neon break end
			end
		end
		m.Parent = room
		shown[i] = m
	end

	-- Rebuild every placed object. Called when the room is (re)built and when
	-- the server hands back a new list.
	function F.render(cityData)
		data = cityData or data
		if not room or not roomCF then return end
		for i, m in shown do m:Destroy() shown[i] = nil end
		for i, p in ((data or {}).placed or {}) do
			draw(i, p)
		end
	end

	-- CityHome calls this when it has built (or rebuilt) an interior.
	function F.attach(model, cf, cityData)
		room, roomCF = model, cf
		F.render(cityData)
	end

	function F.detach()
		for i, m in shown do m:Destroy() shown[i] = nil end
		F.stopPlacing()
		room, roomCF = nil, nil
	end

	---------------------------------------------------------------------
	-- PLACING
	---------------------------------------------------------------------
	-- The ghost follows the player rather than the mouse. On a phone there is
	-- no mouse, and "walk to where you want it and tap" works identically on
	-- both -- which is cheaper than two input paths and reads the same to
	-- everyone.
	-- THE BAR YOU GET WHILE PLACING. Three controls and nothing else: the
	-- room is what you are supposed to be looking at, so this sits at the
	-- bottom and stays out of the way.
	local bar
	local function showBar()
		if bar then bar:Destroy() end
		bar = Instance.new("Frame")
		bar.Name = "FurnishBar"
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -24)
		bar.Size = UDim2.fromOffset(3 * 120 + 2 * T.space.sm, T.tap.std)
		bar.BackgroundTransparency = 1
		bar.Parent = gui
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, T.space.sm)
		l.Parent = bar
		local function slot(label, col, fn)
			local c = Instance.new("Frame")
			c.Size = UDim2.fromOffset(120, T.tap.std)
			c.BackgroundTransparency = 1
			c.Parent = bar
			UI.button(c, label, { size = UDim2.fromOffset(120, T.tap.std),
				color = col, textSize = T.size.md, onClick = fn })
		end
		slot("TURN", C.sky, function() F.rotate(45) end)
		slot("PLACE", C.mint, function() F.confirm() end)
		slot("CANCEL", C.coral, function() F.stopPlacing() end)
	end

	function F.startPlacing(id)
		F.stopPlacing()
		local it = Config.Furn(id) or (Config.SeasonItem(id))
		if not it or not room then return end
		placing = { id = id, r = 0 }
		showBar()
		ghost = K.place(it.inv, roomCF) or fallback(it, roomCF)
		ghost.Name = "FurnGhost"
		for _, d in ghost:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 0.5
				d.CanCollide, d.CanQuery = false, false
			end
		end
		ghost.Parent = room
	end

	function F.stopPlacing()
		if ghost then ghost:Destroy() ghost = nil end
		if bar then bar:Destroy() bar = nil end
		placing = nil
	end

	function F.rotate(by)
		if placing then placing.r = (placing.r + (by or 45)) % 360 end
	end

	-- TAP A PLACED THING TO PICK IT UP AGAIN. Without this the only way to
	-- fix a mistake is to clear the whole room, and a player who cannot undo
	-- one sofa stops arranging anything.
	function F.pickUp(index)
		task.spawn(function()
			local res = remote("unplace", index)
			if res and res.ok then F.render(res.city) end
		end)
	end

	function F.isPlacing() return placing ~= nil end

	-- Called from the city's update loop with the player's position.
	function F.update(pos)
		if not placing or not ghost or not roomCF then return end
		local l = roomCF:PointToObjectSpace(pos)
		-- in front of the player's feet, snapped to the 1-stud grid so things
		-- line up with each other instead of ending up a hair out
		local x = math.clamp(math.floor(l.X + 0.5), -28, 28)
		local z = math.clamp(math.floor(l.Z + 0.5), -20, 20)
		placing.x, placing.z = x, z
		ghost:PivotTo(roomCF * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(placing.r), 0))
	end

	function F.confirm()
		if not placing then return end
		local p = { id = placing.id, x = placing.x or 0, z = placing.z or 0, r = placing.r }
		F.stopPlacing()
		task.spawn(function()
			local res = remote("place", p)
			if res and res.ok then
				F.render(res.city)
			elseif res and res.reason then
				City.toast(res.reason)
			end
		end)
	end

	---------------------------------------------------------------------
	-- THE SHOP
	---------------------------------------------------------------------
	-- Tabs are the categories from Config, not a hand-written list, so a new
	-- category appears here the moment it exists rather than being forgotten.
	function F.openShop(parent, onClose)
		parent = parent or gui
		-- READ THE LIVE SAVE, not whatever render() last saw. The shop can be
		-- opened without ever having entered a room, in which case `data` is
		-- nil and every price would read as unaffordable.
		local city = (ctx and ctx.data and ctx.data.City) or data or {}
		data = city
		local owned = city.furn or {}
		local coins = (ctx and ctx.data and ctx.data.Coins) or 0

		local holder, card = UI.card(parent, UDim2.fromOffset(620, 420),
			UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.paper)
		holder.Name = "FurnishShop"

		UI.text(card, "FURNISH", { Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 12), Font = T.font.display,
			TextSize = T.size.xl, ZIndex = 3 })

		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(1, -24, 1, -120)
		list.Position = UDim2.fromOffset(12, 96)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ZIndex = 3
		list.Parent = card
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(136, 108)
		grid.CellPadding = UDim2.fromOffset(T.space.sm, T.space.sm)
		grid.Parent = list

		local function fill(cat)
			for _, c in list:GetChildren() do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			local items = {}
			for _, f in Config.Furniture do
				if f.cat == cat then table.insert(items, f) end
			end
			-- SEASONAL ITEMS APPEAR IN THEIR OWN TAB ONLY WHILE THEIR MONTH
			-- IS ON. The server refuses an out-of-season buy anyway; hiding
			-- them too means nobody is offered something they cannot have.
            if cat == "season" then
				local s = Config.Season(tonumber(os.date("!*t").month))
				if s then for _, it in s.shop do table.insert(items, it) end end
			end
			for _, f in items do
				local cell = Instance.new("Frame")
				cell.BackgroundTransparency = 1
				cell.Parent = list
				local have = owned[f.id] == true
				local afford = coins >= f.price
				UI.button(cell, have and "OWNED" or ("◉ " .. f.price), {
					size = UDim2.fromOffset(136, 72),
					color = have and C.paper2 or (afford and C.mint or C.paper2),
					textSize = T.size.sm,
					onClick = function()
						if have then
							F.startPlacing(f.id)
							holder:Destroy()
							if onClose then onClose() end
							return
						end
						task.spawn(function()
							local res = remote("buyFurn", f.id)
							if res and res.ok then
								owned[f.id] = true
								coins = (res.data and res.data.Coins) or coins - f.price
								data = res.city or data
								fill(cat)
							elseif res and res.reason then
								City.toast(res.reason)
							end
						end)
					end })
				UI.text(cell, f.name, { Size = UDim2.new(1, 0, 0, 18),
					Position = UDim2.fromOffset(0, 76), Font = T.font.bold,
					TextSize = T.size.xs, TextColor3 = C.inkSoft, ZIndex = 4 })
			end
			list.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 12)
		end

		local tabs = Instance.new("Frame")
		tabs.Size = UDim2.new(1, -24, 0, 40)
		tabs.Position = UDim2.fromOffset(12, 52)
		tabs.BackgroundTransparency = 1
		tabs.ZIndex = 3
		tabs.Parent = card
		local tl = Instance.new("UIListLayout")
		tl.FillDirection = Enum.FillDirection.Horizontal
		tl.Padding = UDim.new(0, T.space.xs)
		tl.Parent = tabs
		local cats = {}
		for _, c in Config.FurnitureCats do table.insert(cats, c) end
		if Config.Season(tonumber(os.date("!*t").month)) then
			table.insert(cats, { id = "season", name = "LIMITED" })
		end
		for _, c in cats do
			local b = Instance.new("Frame")
			b.Size = UDim2.fromOffset(72, T.tap.std)
			b.BackgroundTransparency = 1
			b.Parent = tabs
			UI.button(b, c.name:sub(1, 7), { size = UDim2.fromOffset(72, T.tap.std),
				color = c.id == "season" and C.lav or C.paper2,
				textSize = T.size.xs, textColor = C.ink,
				onClick = function() fill(c.id) end })
		end

		UI.button(card, "DONE", { size = UDim2.fromOffset(140, T.tap.std),
			pos = UDim2.new(0.5, 0, 1, -12), anchor = Vector2.new(0.5, 1),
			color = C.mint, onClick = function()
				holder:Destroy()
				if onClose then onClose() end
			end })

		fill(cats[1].id)
		return holder
	end

	return F
end
