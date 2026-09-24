-- CityGrocery (client): the basket, the till and the fridge.
--
-- THE LOOP. Walk into a grocery store (the SUPER MARKET on the market
-- block, or any corner GROCERY on a shopping street), TAKE things off the
-- shelves into a basket, PAY at the till, and what you bought is in your
-- fridge at home -- where a SNACK is worth a little XP. Leave a store with
-- an unpaid basket and you have left it at the door.
--
-- WHO OWNS WHAT. The basket is client-side: it is a list of wishes until
-- the till. The server prices it from Config, checks you are standing at a
-- till, takes the coins and fills the pantry (data.City.pantry) -- so a
-- client that edits its basket or its prices gets exactly what it pays for.
-- The shelves and tills are venue SPOTS built by CityBuild; this module
-- only says what happens when you use one.
--   deps: UI, Audio, Config, City, S, H, player, remote, earned, cityData
return function(deps)
	local UI, Audio, Config, City, S, H, player = deps.UI, deps.Audio, deps.Config, deps.City, deps.S, deps.H, deps.player
	local remote, earned, cityData = deps.remote, deps.earned, deps.cityData
	local C = UI.C

	local G = { basket = {}, count = 0, store = nil }

	local function fmt(n) return UI.fmt and UI.fmt(n) or tostring(n) end

	function G.total()
		local t = 0
		for id, qty in pairs(G.basket) do
			local g = Config.Grocery(id)
			if g then t += g.price * qty end
		end
		return t
	end
	function G.pantryCount()
		local c = cityData()
		local n = 0
		for _, q in pairs(c and c.pantry or {}) do n += q end
		return n
	end
	function G.pantryNames(max)
		local c = cityData()
		local names = {}
		for id, q in pairs(c and c.pantry or {}) do
			local g = Config.Grocery(id)
			if g then table.insert(names, g.name .. (q > 1 and (" x" .. q) or "")) end
			if #names >= (max or 4) then break end
		end
		return names
	end

	-- the basket pill under the district name; only there while you carry one
	local pill, pillText
	function G.init(root)
		local holder, card = UI.card(root, UDim2.fromOffset(300, 44), UDim2.new(0.5, 0, 0, 210), Vector2.new(0.5, 0), C.paper)
		holder.Visible = false
		pill = holder
		UI.icon(card, "bag", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(8, 5), ZIndex = 3 })
		pillText = UI.text(card, "", { Size = UDim2.new(1, -56, 1, 0), Position = UDim2.fromOffset(48, 0),
			Font = Enum.Font.FredokaOne, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
	end
	local function refreshPill()
		if not pill then return end
		pill.Visible = G.count > 0 and not City.hudOff
		if G.count > 0 then
			pillText.Text = string.format("BASKET  %d item%s  \u{00B7}  %s coins", G.count, G.count == 1 and "" or "s", fmt(G.total()))
		end
	end

	-- TAKE: a shelf spot's act = { grocery = id }
	function G.take(id, v)
		local g = Config.Grocery(id)
		if not g then return end
		if G.count >= Config.BasketMax then
			UI.toast("your basket is full -- go and pay", C.coral)
			Audio.play("Click", 0.8, 0.5)
			return
		end
		G.basket[id] = (G.basket[id] or 0) + 1
		G.count += 1
		G.store = v
		Audio.play("Pop", 1.15 + G.count * 0.02, 0.6)
		UI.toast(string.lower(g.name) .. " in the basket  \u{00B7}  " .. fmt(G.total()) .. " coins so far", C.mintDark)
		refreshPill()
	end

	-- what the till says as you walk up
	function G.tillLine()
		if G.count == 0 then return "nothing in your basket yet -- the shelves are that way" end
		return string.format("%d item%s  \u{00B7}  that'll be %s coins", G.count, G.count == 1 and "" or "s", fmt(G.total()))
	end
	function G.shelfLine(id)
		local g = Config.Grocery(id)
		if not g then return "" end
		local n = G.basket[id] or 0
		return fmt(g.price) .. " coins" .. (n > 0 and ("  \u{00B7}  " .. n .. " in your basket") or "")
	end

	-- PAY: the till spot's act = { checkout = true }
	local paying = false
	function G.checkout()
		if paying then return end
		if G.count == 0 then
			UI.toast("nothing to pay for -- grab something off a shelf", C.coral)
			return
		end
		paying = true
		task.spawn(function()
			local res = remote("checkout", G.basket)
			paying = false
			if res and res.ok then
				local paid, count = res.paid or G.total(), res.count or G.count
				G.basket, G.count, G.store = {}, 0, nil
				refreshPill()
				earned(res, string.format("paid %s coins  \u{00B7}  %d thing%s for the fridge", fmt(paid), count, count == 1 and "" or "s"))
				Audio.play("BigChime", 1.2, 0.7)
				if City.Jobs and City.Jobs.notify then
					City.Jobs.notify("bag", "GROCERIES", "take them home -- they are in your fridge", C.mint)
				end
			else
				earned(res, "")
				Audio.play("Click", 0.8, 0.5)
			end
		end)
	end

	-- SNACK: the fridge at home. The server picks what you eat.
	function G.eat(after)
		task.spawn(function()
			local res = remote("eat")
			if res and res.ok then
				local g = Config.Grocery(res.ate)
				earned(res, "")
				UI.toast("yum! " .. string.lower(g and g.name or "a snack") .. " from the fridge  \u{00B7}  +" .. Config.SnackXP .. " xp", C.mintDark)
				if after then after(true) end
			else
				if res and res.reason then UI.toast(res.reason, C.coral) end
				if after then after(false) end
			end
		end)
	end

	-- walking out with an unpaid basket leaves it at the door
	function G.step(me)
		if G.count == 0 then
			if pill and pill.Visible then refreshPill() end
			return
		end
		if City.hudOff ~= (not pill.Visible) then refreshPill() end
		-- "still in the store" is distance from THIS store's centre, not
		-- whichever room is nearest: at the supermarket's edges the kerb
		-- units are nearer, and the basket was being dropped mid-aisle
		local store = G.store
		local inside = store and (Vector3.new(me.X, 0, me.Z) - Vector3.new(store.pos.X, 0, store.pos.Z)).Magnitude < (store.radius or 26) + 4
		if not inside then
			G.basket, G.count, G.store = {}, 0, nil
			refreshPill()
			UI.toast("you left your basket at the door", C.coral)
			Audio.play("Click", 0.7, 0.5)
		end
	end

	return G
end
