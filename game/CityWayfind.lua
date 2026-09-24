-- CityWayfind (client): "how do I get to X?"
--   W.to(pos, name)   lay a soft ribbon along the streets to somewhere
--   W.clear()         put it away
--   W.step(dt, t, me) eat the ribbon behind you, breathe it, dim it by hour
--
-- The ribbon is drawn ON THE ROAD, in the gutter lane, not floating: it reads
-- as a painted line that happens to glow, which is the point -- you follow it
-- with your eyes down the street rather than tracking a chain of markers.
--
-- Two things here exist because of the hour:
--
-- 1. IT DIMS WITH THE DAY. At noon a ribbon needs to be bright enough to see
--    against pale concrete; at 2am the same ribbon is the brightest thing in
--    a dark town and reads as a runway. It reads CityWeather's current look
--    and scales itself, so it is an accent at every hour instead of only at
--    the one hour it was authored at.
--
-- 2. IT ROUTES ON THE ROAD GRID, AND SAYS SO WHEN IT CANNOT. The airport is
--    across the bay and the grid does not go there. Rather than drawing a
--    confident line over open water, the ribbon stops at the last real road
--    and tells you what to do next.
--   deps: K, Places, UI, Audio, player, City

return function(deps)
	local K, Places, UI, Audio, player, City = deps.K, deps.Places, deps.UI, deps.Audio, deps.player, deps.City
	local V, rgb = K.V, K.rgb
	local part = deps.Models.part
	local CITY = Places.CITY
	local ROADS = Places.CityRoads
	local W = { dest = nil }

	-- the gutter lane: just inside the kerb, where a painted line would go
	local LANES = {}
	for _, r in ROADS do
		table.insert(LANES, r - 13)
		table.insert(LANES, r + 13)
	end
	local EDGE = ROADS[#ROADS] + 60
	local function nearestLane(v)
		local best, bd = LANES[1], math.huge
		for _, l in LANES do
			local d = math.abs(l - v)
			if d < bd then best, bd = l, d end
		end
		return best
	end
	local function flat(v) return V(v.X, 0, v.Z) end
	local function onGrid(p) return math.abs(p.X) <= EDGE and math.abs(p.Z) <= EDGE end

	---------------------------------------------------------------------------
	-- THE ROUTE: from you, out to a lane, along the grid, in to the door
	---------------------------------------------------------------------------
	local function route(from, to)
		local corners = { flat(from) }
		local reachable = onGrid(to)
		local target = to
		if not reachable then
			-- clamp to the edge of the road network and stop honestly there
			target = V(math.clamp(to.X, -EDGE, EDGE), 0, math.clamp(to.Z, -EDGE, EDGE))
		end
		target = flat(target)
		local a = flat(from)
		-- pick the axis that gets you onto a lane with the shorter detour
		local laneX, laneZ = nearestLane(a.X), nearestLane(a.Z)
		local outX, outZ = nearestLane(target.X), nearestLane(target.Z)
		if math.abs(laneX - a.X) <= math.abs(laneZ - a.Z) then
			table.insert(corners, V(laneX, 0, a.Z))
			table.insert(corners, V(laneX, 0, outZ))
			table.insert(corners, V(outX, 0, outZ))
			table.insert(corners, V(outX, 0, target.Z))
		else
			table.insert(corners, V(a.X, 0, laneZ))
			table.insert(corners, V(outX, 0, laneZ))
			table.insert(corners, V(outX, 0, outZ))
			table.insert(corners, V(target.X, 0, outZ))
		end
		table.insert(corners, target)
		-- drop any corner that doubles back on itself
		local out = { corners[1] }
		for i = 2, #corners do
			if (corners[i] - out[#out]).Magnitude > 4 then table.insert(out, corners[i]) end
		end
		return out, reachable
	end

	---------------------------------------------------------------------------
	-- THE RIBBON
	---------------------------------------------------------------------------
	local model, segs, endCap = nil, {}, nil
	local RIBBON = rgb(150, 226, 140)

	function W.clear()
		if model then model:Destroy() end
		model, segs, endCap = nil, {}, nil
		W.dest, W.name, W.short = nil, nil, nil
	end

	function W.to(pos, name)
		local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		W.clear()
		local from = hrp.Position - CITY
		local corners, reachable = route(from, pos)
		model = Instance.new("Model")
		model.Name = "Wayfinding"
		local y = K.PAD_Y + 0.07
		for c = 1, #corners - 1 do
			local p0, p1 = corners[c], corners[c + 1]
			local len = (p1 - p0).Magnitude
			if len > 1 then
				local n = math.max(1, math.floor(len / 11))
				for k = 0, n - 1 do
					local a = p0:Lerp(p1, k / n)
					local b = p0:Lerp(p1, (k + 0.62) / n)
					local mid = (a + b) / 2
					local cf = CFrame.lookAt(CITY + V(mid.X, y, mid.Z), CITY + V(p1.X, y, p1.Z))
					local seg = part(model, V(5.2, 0.12, (b - a).Magnitude), cf, RIBBON, Enum.Material.Neon, { noShadow = true })
					seg.CanCollide, seg.CanQuery, seg.CanTouch = false, false, false
					table.insert(segs, { p = mid, part = seg, i = #segs + 1 })
				end
			end
		end
		-- a ring where it ends, and a word about what to do if the road stops
		local last = corners[#corners]
		endCap = part(model, V(0.4, 11, 11), CFrame.new(CITY + V(last.X, y + 0.1, last.Z)) * CFrame.Angles(0, 0, math.pi / 2),
			RIBBON, Enum.Material.Neon, { shape = Enum.PartType.Cylinder, noShadow = true, transparency = 0.4 })
		endCap.CanCollide, endCap.CanQuery, endCap.CanTouch = false, false, false
		model.Parent = K.actors
		W.dest, W.name, W.reachable = pos, name, reachable
		Audio.play("Chime", 1.25, 0.6)
		if reachable then
			UI.toast("following the green line to " .. (name or "your stop"), UI.C.mintDark)
		else
			UI.toast((name or "that") .. " is off the road grid -- the line takes you as far as the road goes", UI.C.gold)
		end
	end

	---------------------------------------------------------------------------
	-- PER FRAME: eat what you have passed, breathe, and follow the hour
	---------------------------------------------------------------------------
	local acc = 0
	function W.step(dt, t, me)
		if not model then return end
		acc += dt
		if acc < 0.1 then return end
		acc = 0
		-- how bright should a glowing line be right now? At noon it competes
		-- with sunlit concrete; at midnight it is the only lit thing in frame.
		local look = City.Weather and City.Weather.look()
		local night = look and look.lamps or 0
		local base = 0.28 + night * 0.34            -- MORE transparent after dark
		local pulse = 0.06 * math.sin(t * 2.2)
		local reached = 0
		for _, s in segs do
			if s.part.Parent then
				local d = (flat(me) - s.p).Magnitude
				if d < 9 then
					s.done = true
				end
				if s.done then
					s.part.Transparency = 1
				else
					-- a travelling highlight so the line reads as a direction
					local wave = math.sin(t * 2.6 - s.i * 0.35) * 0.5 + 0.5
					s.part.Transparency = math.clamp(base + pulse - wave * 0.22, 0.06, 0.96)
					reached += 1
				end
			end
		end
		if endCap then endCap.Transparency = math.clamp(0.3 + night * 0.3 + pulse, 0.1, 0.9) end
		-- arrived
		if W.dest and (flat(me) - flat(W.dest)).Magnitude < 16 then
			UI.toast("you're here: " .. (W.name or "your stop"), UI.C.mintDark)
			Audio.play("BigChime", 1.2, 0.7)
			W.clear()
		elseif reached == 0 and #segs > 0 then
			W.clear()
		end
	end

	return W
end
