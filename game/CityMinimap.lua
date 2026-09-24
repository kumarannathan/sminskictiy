-- CityMinimap: the always-on corner map.
--   deps: UI, Places
--
-- WHAT IT IS FOR. The city map already exists, but it is a modal: you only
-- see the shape of the town when you stop playing to look at it. A town you
-- cannot picture is a town you wander rather than travel, and a job marker you
-- cannot see is a job you forget you accepted. This puts both on screen all
-- the time, and costs one Position write a frame to do it.
--
-- HOW IT DRAWS, AND WHY NOT THE OBVIOUS WAY. The obvious minimap redraws the
-- visible neighbourhood every frame. This one builds the WHOLE city once, at
-- SPAN pixels across, into a frame that is far bigger than the window it sits
-- in, and then slides that frame under a clipped circle. Panning a parent is
-- one property write; rebuilding is dozens. It also means the pins are
-- ordinary children placed once at their own coordinates and never touched
-- again -- they move because the world moves under them.
--
-- IT DOES NOT ROTATE. The disc is north-locked and the player arrow spins
-- inside it. A rotating map means the district you learned as "north of the
-- park" is somewhere new every time you turn around, which is exactly the
-- mental model the map exists to build.

return function(deps)
	local UI, Places = deps.UI, deps.Places
	local C = UI.C
	local HALF = Places.CITY_HALF
	local ROADS = Places.CityRoads

	local M = {}
	local SPAN = 1500 -- the whole city, in minimap pixels

	-- city studs -> minimap pixels. Z is flipped because +Z is south on screen.
	local function toMap(x, z)
		return (x + HALF) / (2 * HALF) * SPAN, (HALF - z) / (2 * HALF) * SPAN
	end
	M.toMap = toMap
	M.SPAN = SPAN

	local function corner(o, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = r or UDim.new(1, 0)
		c.Parent = o
		return c
	end
	local function box(parent, props)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		for k, v in props do f[k] = v end
		f.Parent = parent
		return f
	end

	-- ZOOM. How many city studs the disc shows across its face. Lower is more
	-- zoomed in. 900 puts about three blocks on screen, which is far enough to
	-- see the next junction and close enough that a pin means "over there"
	-- rather than "somewhere in that quarter of town".
	M.ZOOM = 900

	---------------------------------------------------------------------------
	-- BUILD. Returns a handle; the caller parents `mm.holder` and positions it.
	---------------------------------------------------------------------------
	function M.build(parent, size, onTap)
		local mm = { size = size }

		local holder = box(parent, {
			Name = "Minimap", BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
		})
		mm.holder = holder

		-- the paper rim, on the same 9-slice disc the rest of the UI uses
		local rim = box(holder, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.paper })
		corner(rim)
		UI.skin(rim, "disc", 0.5)

		local inset = math.max(5, math.floor(size * 0.055))
		local view = box(holder, {
			Name = "View",
			Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
			Position = UDim2.fromOffset(inset, inset),
			BackgroundColor3 = Color3.fromRGB(176, 214, 146),
			ClipsDescendants = true,
			ZIndex = 3,
		})
		corner(view)
		mm.view = view
		mm.half = (size - inset * 2) / 2

		-- THE WORLD, BUILT ONCE.
		-- A UIScale on this frame is what turns SPAN pixels of city into the
		-- ZOOM studs the disc is supposed to show, so changing the zoom never
		-- touches a single child's position.
		local world = box(view, {
			Name = "World", BackgroundTransparency = 1,
			Size = UDim2.fromOffset(SPAN, SPAN), ZIndex = 3,
		})
		mm.world = world
		local wscale = Instance.new("UIScale")
		wscale.Scale = (size - inset * 2) / (M.ZOOM / (2 * HALF) * SPAN)
		wscale.Parent = world
		mm.wscale = wscale
		mm.pxPerStud = SPAN / (2 * HALF) * wscale.Scale

		-- districts (1), roads (2), pins (4), the player (6)
		for _, d in Places.CityDistricts do
			local x0, y0 = toMap(d.x0, d.z1)
			local x1, y1 = toMap(d.x1, d.z0)
			box(world, {
				BackgroundColor3 = d.color, BackgroundTransparency = 0.18,
				Position = UDim2.fromOffset(x0, y0),
				Size = UDim2.fromOffset(x1 - x0, y1 - y0),
				ZIndex = 3,
			})
		end
		local roadW = math.max(3, SPAN * 0.006)
		for _, r in ROADS do
			local rx, ry = toMap(r, r)
			box(world, { BackgroundColor3 = Color3.fromRGB(250, 246, 236), ZIndex = 4,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(rx, 0), Size = UDim2.fromOffset(roadW, SPAN) })
			box(world, { BackgroundColor3 = Color3.fromRGB(250, 246, 236), ZIndex = 4,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(0, ry), Size = UDim2.fromOffset(SPAN, roadW) })
		end

		-- PINS. A pin is placed once, in world coordinates, and never moved.
		mm.pins = {}
		function mm.pin(name, pos, col, r)
			if mm.pins[name] then mm.pins[name]:Destroy() mm.pins[name] = nil end
			if not pos then return end
			local px, py = toMap(pos.X, pos.Z)
			r = r or 9
			local f = box(world, {
				Name = name, BackgroundColor3 = col, ZIndex = 5,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(px, py),
				Size = UDim2.fromOffset(r * 2, r * 2),
			})
			corner(f)
			local s = Instance.new("UIStroke")
			s.Thickness = 3
			s.Color = C.white
			s.Parent = f
			mm.pins[name] = f
			return f
		end

		-- THE PLAYER, fixed at the centre of the disc. The needle is a separate
		-- rotating rectangle rather than a rotated arrow image, because there is
		-- no arrow in the icon set and GuiObject.Rotation costs nothing.
		local me = box(view, {
			Name = "Me", BackgroundTransparency = 1, ZIndex = 6,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
		})
		local needle = box(me, {
			Name = "Needle", BackgroundColor3 = C.paper, ZIndex = 6,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.28),
			Size = UDim2.fromOffset(7, 15),
		})
		corner(needle, UDim.new(0, 3))
		local ns = Instance.new("UIStroke") ns.Thickness = 2 ns.Color = C.ink ns.Parent = needle
		local dot = box(me, {
			Name = "Dot", BackgroundColor3 = C.paper, ZIndex = 7,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(13, 13),
		})
		corner(dot)
		local ds = Instance.new("UIStroke") ds.Thickness = 2.5 ds.Color = C.ink ds.Parent = dot
		mm.me, mm.needle = me, needle

		-- OFF-DISC OBJECTIVE. When the thing you are heading for is outside the
		-- circle the pin is simply not drawn -- so without this the minimap goes
		-- quiet at exactly the moment it is most useful. The chevron rides the
		-- rim at the objective's bearing instead.
		local chev = box(view, {
			Name = "Chevron", BackgroundColor3 = C.coral, ZIndex = 8, Visible = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
		})
		corner(chev, UDim.new(0, 4))
		local cs = Instance.new("UIStroke") cs.Thickness = 2.5 cs.Color = C.white cs.Parent = chev
		mm.chev = chev

		-- north tick: the one thing that says the disc is not rotating
		local n = box(holder, {
			BackgroundColor3 = C.ink, ZIndex = 9,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 1),
			Size = UDim2.fromOffset(24, 16),
		})
		corner(n, UDim.new(0, 8))
		UI.text(n, "N", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne,
			TextSize = 11, TextColor3 = C.paper, ZIndex = 10 })

		local tap = Instance.new("TextButton")
		tap.Name = "Tap"
		tap.Text = ""
		tap.AutoButtonColor = false
		tap.BackgroundTransparency = 1
		tap.Size = UDim2.fromScale(1, 1)
		tap.ZIndex = 12
		tap.Parent = holder
		tap.Activated:Connect(function() if onTap then onTap() end end)
		mm.tap = tap

		return mm
	end

	---------------------------------------------------------------------------
	-- STEP. Called once a frame with the player's city-relative position, the
	-- camera's heading in degrees, and the current objective (or nil).
	---------------------------------------------------------------------------
	function M.step(mm, me, headingDeg, target)
		if not mm or not mm.holder.Visible then return end
		local px, py = toMap(me.X, me.Z)
		local k = mm.wscale.Scale
		-- the world slides so that (px, py) lands under the centre of the disc.
		-- Dividing by the scale is not optional: Position is applied BEFORE the
		-- UIScale, so an unscaled offset drifts by a factor of k as you walk.
		mm.world.Position = UDim2.fromOffset(mm.half / k - px, mm.half / k - py)
		mm.needle.Rotation = headingDeg

		if not target then
			mm.chev.Visible = false
			return
		end
		local tx, ty = toMap(target.X, target.Z)
		local dx, dy = (tx - px) * k, (ty - py) * k
		local d = math.sqrt(dx * dx + dy * dy)
		local edge = mm.half - 12
		if d <= edge then
			mm.chev.Visible = false
		else
			mm.chev.Visible = true
			mm.chev.Position = UDim2.new(0.5, dx / d * edge, 0.5, dy / d * edge)
			mm.chev.Rotation = math.deg(math.atan2(dy, dx)) + 45
		end
	end

	return M
end
