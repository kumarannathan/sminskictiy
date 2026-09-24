-- SminskiTitle (ReplicatedFirst): the first thing a new player ever sees.
--
-- THREE PHASES, one script:
--   1 LOADING  five plates of key art, the logo across the top, a progress
--              bar, and a PLAY button that arrives fifteen seconds in.
--   2 MENU     built only when somebody asks for it from the city HUD, over
--              a live camera flying slowly over the real downtown.
--   3 GONE     fades out and hands the player to the client script.
--
-- WHY THIS LIVES IN ReplicatedFirst. Everything else in the game is in
-- StarterPlayerScripts, which does not run until the client has replicated a
-- fair amount. ReplicatedFirst runs before that, which is the entire point:
-- the twenty-odd seconds this is covering are the twenty seconds a player
-- currently spends watching a half-built city assemble around them.
--
-- THE BAR IS SIMULATED, AND THE PREVIOUS VERSION OF THIS COMMENT SAID THE
-- OPPOSITE. It used to read "THE BAR NEVER LIES" and it was wired to real
-- block streaming, which meant its length was set by the player's hardware:
-- the slowest phone got the longest bar and was told so in percentages all
-- the way down. It now runs the same fifteen seconds for everybody.
--
-- THE WAIT ITSELF DID NOT GO ANYWHERE. The city still streams behind this
-- card, and the city's own curtain (City.lua, "ARRIVING IN SMINSKI CITY...")
-- is still underneath: it waits for the blocks near you and lifts on its own
-- after fifteen seconds. Pressing PLAY early hands you to that, not to a hole
-- in the ground. What was removed is the reporting, not the safety.
--
-- AND IT ALWAYS LIFTS. PLAY appears on a plain task.delay that nothing can
-- gate, with a second failsafe behind it. A loading screen that traps someone
-- forever is worse than no loading screen.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInput = game:GetService("UserInputService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------------
-- THE HANDSHAKE. Created here because this script runs first; the client
-- script waits for both.
--   SR_Progress  0..1, written by the client as the city streams in
--   SR_Play      fired here when the player presses PLAY
---------------------------------------------------------------------------
-- SR_Progress IS STILL CREATED AND IS NOW NEVER READ HERE. The bar stopped
-- tracking it (see THE BAR IS A PERFORMANCE below), but SminskiRunner gates
-- its whole title handshake on finding this value -- `if bar and playEvent`,
-- SminskiRunner.client.lua:2443 -- so deleting it would silently disable the
-- HUD hold, the peek routing and PLAY itself.
local progress = Instance.new("NumberValue")
progress.Name = "SR_Progress"
progress.Value = 0
progress.Parent = ReplicatedFirst
local playEvent = Instance.new("BindableEvent")
playEvent.Name = "SR_Play"
playEvent.Parent = ReplicatedFirst
-- what the player picked on the menu, so the client can act on it
local choice = Instance.new("StringValue")
choice.Name = "SR_Choice"
choice.Value = "none"
choice.Parent = ReplicatedFirst

---------------------------------------------------------------------------
-- LOOK. Kept in one table so it matches UI.lua without requiring it (this
-- script runs long before StarterPlayerScripts exists).
---------------------------------------------------------------------------
local C = {
	cream = Color3.fromRGB(255, 248, 232),
	paper = Color3.fromRGB(252, 246, 230),
	ink = Color3.fromRGB(62, 58, 78),
	inkSoft = Color3.fromRGB(128, 122, 140),
	mint = Color3.fromRGB(150, 210, 140),
	mintDark = Color3.fromRGB(96, 168, 96),
	deep = Color3.fromRGB(46, 84, 46),
	gold = Color3.fromRGB(245, 196, 80),
	sky = Color3.fromRGB(150, 200, 245),
	coral = Color3.fromRGB(255, 130, 120),
}
local DISPLAY = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamBold
---------------------------------------------------------------------------
-- ASSETS. The loader's background is five plates of key art, shown in order.
--
-- NO KEN BURNS. The previous version pushed slowly into every plate. That
-- looks expensive on a desktop monitor and looks like a fault on a phone --
-- the crop drifts, the character walks out of frame, and the whole thing
-- reads as the image failing to sit still. The plates are held dead still
-- now. The only thing that moves is the crossfade between them.
--
-- Every slot is optional and a blank id is skipped, so this works with
-- however many are uploaded.
---------------------------------------------------------------------------
local LOGO = "rbxassetid://136099327774422"     -- game/art/intro/logo_sminskicity.png
local TITLE_BG = "rbxassetid://77179164548904"  -- the balcony: apt4's last frame
-- FIVE PLATES, three seconds each: exactly one pass in the fifteen seconds
-- before PLAY appears, ending on the skyline. The order is an arc -- who you
-- are, arriving, the street, living here, and then the city itself.
local PLATE_SECS = 3.0
local PLATES = {
	"rbxassetid://95516110778296",   -- 1 the meadow     art/intro/loader/load1_meadow.jpg
	"rbxassetid://75406673102334",   -- 2 the bus stop   art/intro/loader/load3_busstop.jpg
	"rbxassetid://136231265586650",  -- 3 the toy store  art/intro/loader/load5_toystore.jpg
	"rbxassetid://99317129880419",   -- 4 the cafe       art/intro/loader/load2_cafe.jpg
	"rbxassetid://94440570554992",   -- 5 the city map   art/intro/loader/load4_citymap.jpg
}
-- the older ten-plate set, kept ONLY as a fallback. If PLATES is ever emptied
-- -- a moderation takedown, an id pasted wrong -- the card shows these rather
-- than a bare gradient, because a blank loading screen is the one outcome
-- this file exists to prevent.
local LEGACY_PLATES = {
	"rbxassetid://134163170406525", "rbxassetid://113037420070292",
	"rbxassetid://96657732221618", "rbxassetid://92910256829411",
	"rbxassetid://76476963517733", "rbxassetid://122819888716878",
	"rbxassetid://118270090154190", "rbxassetid://133671440102454",
	"rbxassetid://114784316039496", "rbxassetid://82061401341573",
}
local function anyOf(t)
	for _, v in t do
		if v ~= "" then return true end
	end
	return false
end
if not anyOf(PLATES) then PLATES = LEGACY_PLATES end

-- EVERY MUTABLE FLAG THIS SCREEN HAS, in one block, at the top.
--
-- Six separate bugs in this file were "declared below the function that reads
-- it" -- a `local` is invisible above its own declaration, and these are read
-- by functions written hundreds of lines apart. So they all live here now,
-- whether or not the thing that sets them is nearby.
local hasEntered = false   -- ever been in the world? START GAME vs RESUME
local picked = false       -- a pick is in flight (guards a double press)
local peeking = false      -- a screen is open over the menu
local menuShown = false    -- the menu has been built (guards a rebuild)
local refreshMenuLabels
local buildMenu          -- built lazily; see PHASE 2
local sweeping = false     -- keep re-hiding world billboards under the menu

-- NOTHING TO SHOW is the one case worth saying out loud, because the card
-- would otherwise be a flat gradient and nobody would know why.
if not anyOf(PLATES) then
	warn("[SminskiTitle] no loader plates. Upload game/art/intro/loader/*.jpg and "
		.. "paste the returned ids into PLATES.")
end

local gui = Instance.new("ScreenGui")
gui.Name = "SminskiTitle"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
-- GUARD. This screen is the only thing between a new player and a blank
-- window, and it is named Sminski* like everything else here -- so if some
-- other startup pass ever sweeps PlayerGui again, put it back rather than
-- leaving somebody staring at nothing.
gui.AncestryChanged:Connect(function(_, parent)
	if not parent then
		warn("[SminskiTitle] something removed the title screen -- restoring it")
		task.defer(function() gui.Parent = player:FindFirstChild("PlayerGui") end)
	end
end)

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = C.paper
	for k, v in props or {} do f[k] = v end
	f.Parent = parent
	return f
end
local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
	return c
end
local function text(parent, str, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = str
	t.Font = DISPLAY
	t.TextColor3 = C.ink
	t.TextSize = 20
	for k, v in props or {} do t[k] = v end
	t.Parent = parent
	return t
end

-- FADES A LABEL AND ITS OUTLINE TOGETHER.
--
-- A UIStroke's Transparency is a separate property from its label's
-- TextTransparency, so fading only the text leaves the outline behind at
-- full opacity -- which read as shadows lingering through every transition.
local function fadeText(label, ti, transparency)
	TweenService:Create(label, ti, { TextTransparency = transparency }):Play()
	local st = label:FindFirstChildWhichIsA("UIStroke")
	if st then
		TweenService:Create(st, ti, { Transparency = 1 - (1 - transparency) * 0.94 }):Play()
	end
end

---------------------------------------------------------------------------
-- PHASE 1: LOADING
---------------------------------------------------------------------------
-- NAMED, all of it. Everything on this screen used to be called "Frame" or
-- "ImageLabel", which means the only way to address any of it from a test is
-- GetChildren()[n] -- and the order of that is not a contract.
local loadScreen = frame(gui, { Name = "LoadCard", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(176, 214, 244), ZIndex = 2 })
-- a soft sky behind it all, so a plate that fails to load still looks deliberate
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(186, 222, 250)),
		ColorSequenceKeypoint.new(0.62, Color3.fromRGB(226, 240, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(252, 240, 216)),
	})
	g.Rotation = 90
	g.Parent = loadScreen
end
---------------------------------------------------------------------------
-- THE CAROUSEL. Two stacked plates crossfading, and nothing else moves.
--
-- IT LOOPS FOREVER rather than stopping on the last plate. Somebody who
-- leaves the tab open for two minutes should come back to a screen that is
-- still alive, not to a frozen JPEG that looks like a crash.
---------------------------------------------------------------------------
local function plate(z)
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.ImageTransparency = 1
	i.ScaleType = Enum.ScaleType.Crop
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Size = UDim2.fromScale(1, 1)
	i.Position = UDim2.fromScale(0.5, 0.5)
	i.ZIndex = z
	i.Parent = loadScreen
	return i
end
local plateA, plateB = plate(2), plate(3)
plateA.Name, plateB.Name = "PlateA", "PlateB"

-- PRELOAD THE SET. Without this, plate 2 is a grey rectangle for the first
-- second it is on screen -- which is the most visible possible moment for it,
-- because the crossfade draws the eye straight to it. A failed preload is not
-- fatal (a moderated or missing id throws), so the whole thing is wrapped and
-- the carousel runs either way.
task.spawn(function()
	pcall(function()
		local probes = {}
		for _, id in PLATES do
			if id ~= "" then
				local i = Instance.new("ImageLabel")
				i.Image = id
				table.insert(probes, i)
			end
		end
		game:GetService("ContentProvider"):PreloadAsync(probes)
		for _, i in probes do i:Destroy() end
	end)
end)

task.spawn(function()
	if #PLATES == 0 then return end
	local front, back = plateA, plateB
	local n = 0
	while loadScreen.Visible do
		n += 1
		local id = PLATES[(n - 1) % #PLATES + 1]
		-- a blank slot still costs a beat. Skipping it with `continue` and no
		-- wait turns an all-blank table into a tight loop that hangs the client
		-- on the first frame it ever draws.
		if id == "" then
			task.wait(0.2)
			continue
		end
		back.Image = id
		-- THE INCOMING PLATE GOES ON TOP, every time. Both plates keep a fixed
		-- ZIndex in the obvious version of this, which means every other
		-- transition fades the new image in BEHIND the old one -- invisible for
		-- 0.6s, then a hard reveal when the old one finally goes. Reassigning
		-- the pair each cycle is what makes it an actual dissolve.
		back.ZIndex, front.ZIndex = 3, 2
		TweenService:Create(back, TweenInfo.new(0.6), { ImageTransparency = 0 }):Play()
		task.wait(0.62)
		front.ImageTransparency = 1   -- fully covered by now, so this cannot be seen
		front, back = back, front
		-- HOLD BY THE CLOCK, NOT BY COUNTING WAITS. The obvious version adds 0.05
		-- per task.wait(0.05) and calls that the elapsed time, but task.wait
		-- returns on the next frame AFTER the delay, so every iteration loses a
		-- few milliseconds. Measured, that turned a 3.00s plate into ~3.41s --
		-- 13% long, which pushed the fifth plate past PLAY and meant nobody ever
		-- saw the shot the set was ordered to end on.
		local until_ = os.clock() + (PLATE_SECS - 0.62)
		while os.clock() < until_ and loadScreen.Visible do
			task.wait(0.05)
		end
	end
end)

-- SCRIMS, top and bottom. The logo sits on sky and the bar sits on pavement,
-- and the picture underneath both of them changes every three seconds -- so
-- neither can rely on what is behind it. Two soft gradients make the type
-- readable on all five plates without dimming the middle of the frame, which
-- is where the character always is.
local function scrim(top)
	local s = frame(loadScreen, { Size = UDim2.new(1, 0, 0.32, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 4,
		AnchorPoint = top and Vector2.new(0.5, 0) or Vector2.new(0.5, 1),
		Position = top and UDim2.fromScale(0.5, 0) or UDim2.fromScale(0.5, 1) })
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = top
		and NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.42), NumberSequenceKeypoint.new(1, 1) })
		or NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.32) })
	g.Parent = s
	return s
end
scrim(true).Name = "ScrimTop"
scrim(false).Name = "ScrimBottom"

-- THE LOGO SITS AT THE TOP, over the top scrim, where a masthead goes -- not
-- in the middle of the frame across the character's face.
local logo = Instance.new("ImageLabel")
logo.BackgroundTransparency = 1
logo.Image = LOGO
logo.ScaleType = Enum.ScaleType.Fit
logo.AnchorPoint = Vector2.new(0.5, 0)
logo.Size = UDim2.fromScale(0.34, 0.22)
logo.Position = UDim2.fromScale(0.5, 0.045)
logo.Name = "LoaderLogo"
logo.ZIndex = 8
logo.Parent = loadScreen

-- THE BAR, along the bottom, out of the way of whatever is playing behind it
local barWrap = frame(loadScreen, { Name = "BarCard", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(0.62, 0, 0, 74),
	Position = UDim2.new(0.5, 0, 1, -34), BackgroundColor3 = C.paper, BackgroundTransparency = 0.12, ZIndex = 5 })
corner(barWrap, 20)
local loadLabel = text(barWrap, "LOADING ASSETS", { Name = "Status", Size = UDim2.new(1, -140, 0, 22), Position = UDim2.fromOffset(22, 12),
	TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.ink, ZIndex = 6 })
local pctLabel = text(barWrap, "0%", { Name = "Percent", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(110, 22),
	Position = UDim2.new(1, -22, 0, 12), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.mintDark, ZIndex = 6 })
local track = frame(barWrap, { Name = "Track", Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(22, 42),
	BackgroundColor3 = Color3.fromRGB(226, 220, 206), ZIndex = 6 })
corner(track, 8)
local fill = frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.mint, ZIndex = 7 })
corner(fill, 8)
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(C.mint, C.mintDark)
	g.Parent = fill
end
-- THE TIP LINE IS WHITE NOW, not ink. It used to sit on a cream card; it now
-- sits on the bottom scrim over a photograph, and dark text on that is a
-- smudge on two of the five plates.
local tip = text(loadScreen, "", { Name = "Tip", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(0.7, 0, 0, 26),
	Position = UDim2.new(0.5, 0, 1, -122), Font = BODY, TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.08, ZIndex = 6 })
do
	local st = Instance.new("UIStroke")
	st.Thickness = 2.4
	st.Color = Color3.fromRGB(30, 34, 40)
	st.Transparency = 0.25
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Parent = tip
end
-- tips teach the actual loop, so the wait does some work
local TIPS = {
	"Walk up to the JOB CENTER downtown to start a career.",
	"The pizzeria pays better the faster and neater you cook.",
	"Your shops keep earning while you are away -- let a shift finish for +50%.",
	"A whole day passes every 30 minutes. Weather comes and goes.",
	"Press E on anything with a little green dot.",
	"Apartments, townhouses and brownstones -- five floor plans to pick from.",
	"Fifteen whole-body looks. Your capsule colour shows through some of them.",
	"The green line on the road takes you wherever you asked to go.",
	"Taxi, deliveries, street cleaning, the fields -- all of it counts as work.",
	"Tap MY SHOPS any time to collect what your businesses have banked.",
}

---------------------------------------------------------------------------
-- PLAY. It appears fifteen seconds in, and that is the only rule it obeys.
--
-- IT IS NOT GATED ON THE CITY BEING READY, and that is the whole point of it.
-- The old screen would not let anyone in until streaming had finished, which
-- meant the people on the slowest devices -- exactly the people closest to
-- closing the tab -- waited the longest to be offered anything at all. Now
-- everybody gets the same fifteen seconds and the same button.
--
-- WHAT STOPS THAT BEING RECKLESS is that the city has its own curtain
-- underneath this one (City.lua, "ARRIVING IN SMINSKI CITY..."). It waits for
-- the blocks near you and lifts by itself after fifteen seconds. Pressing
-- PLAY early hands you to that, not to a hole in the ground.
---------------------------------------------------------------------------
local PLAY_AT = 15            -- seconds from the first frame of the card
local playBtn = Instance.new("TextButton")
playBtn.AnchorPoint = Vector2.new(0.5, 1)
playBtn.Size = UDim2.fromOffset(300, 78)
playBtn.Position = UDim2.new(0.5, 0, 1, -162)
playBtn.BackgroundColor3 = C.mint
playBtn.AutoButtonColor = false
playBtn.Text = ""
playBtn.Name = "PlayButton"
playBtn.ZIndex = 10
playBtn.Visible = false
playBtn.Parent = loadScreen
corner(playBtn, 26)
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(C.mint, C.mintDark)
	g.Rotation = 90
	g.Parent = playBtn
	local st = Instance.new("UIStroke")
	st.Thickness = 4
	st.Color = Color3.new(1, 1, 1)
	st.Transparency = 0.5
	st.Parent = playBtn
end
local playScale = Instance.new("UIScale")
playScale.Parent = playBtn
local playLab = text(playBtn, "PLAY", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack,
	TextSize = 38, TextColor3 = Color3.new(1, 1, 1), ZIndex = 11 })
do
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(34, 60, 34)
	st.Transparency = 0.3
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Parent = playLab
end
playBtn.MouseEnter:Connect(function()
	TweenService:Create(playScale, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Scale = 1.06 }):Play()
end)
playBtn.MouseLeave:Connect(function()
	TweenService:Create(playScale, TweenInfo.new(0.16), { Scale = 1 }):Play()
end)

-- BRINGING IT IN. Separate from the timer that calls it, because Studio needs
-- to be able to call this on demand -- a button that only ever appears after
-- a fifteen-second wall clock is a button QA cannot test more than four times
-- a minute.
local playShown = false
local function revealPlay()
	if playShown or not loadScreen.Visible then return end
	playShown = true
	playBtn.Visible = true
	playScale.Scale = 0.72
	playBtn.BackgroundTransparency = 1
	TweenService:Create(playScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	TweenService:Create(playBtn, TweenInfo.new(0.28), { BackgroundTransparency = 0 }):Play()
	-- and then it breathes, so it reads as a thing to press rather than a
	-- green label that happens to be there
	task.spawn(function()
		while playBtn.Visible and loadScreen.Visible do
			TweenService:Create(playScale, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Scale = 1.035 }):Play()
			task.wait(0.9)
			TweenService:Create(playScale, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			task.wait(0.9)
		end
	end)
end

---------------------------------------------------------------------------
-- PHASE 2: THE TITLE MENU, over a live camera above the real downtown
---------------------------------------------------------------------------
local titleScreen = frame(gui, { Name = "TitleMenu", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
-- a gentle vignette so the menu reads over a bright city
local shade = frame(titleScreen, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.72, ZIndex = 1 })
local titleBg
if TITLE_BG ~= "" then
	titleBg = Instance.new("ImageLabel")
	titleBg.BackgroundTransparency = 1
	titleBg.Image = TITLE_BG
	titleBg.ScaleType = Enum.ScaleType.Crop
	titleBg.Size = UDim2.fromScale(1, 1)
	titleBg.ZIndex = 0
	titleBg.Parent = titleScreen
	-- the video ends on this exact framing, so the cut between them is
	-- invisible and the menu appears to settle onto the last shot
	shade.BackgroundTransparency = 0.82
end
local titleLogo = logo:Clone()
titleLogo.Size = UDim2.fromScale(0.38, 0.3)
titleLogo.Position = UDim2.fromScale(0.5, 0.26)
titleLogo.ZIndex = 3
titleLogo.Parent = titleScreen

local menu = frame(titleScreen, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(460, 300),
	Position = UDim2.fromScale(0.5, 0.46), BackgroundTransparency = 1, ZIndex = 3 })
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = menu

-- THE MENU ITEMS: plain bracketed white text, no button plates.
--
-- The background is a photograph of the game, and a stack of coloured pills
-- sat on top of it like a web form -- covering the art to say what the art
-- already says. White text with a hard dark stroke reads over anything, which
-- is the only thing the plate was buying, and it lets the picture through.
--
-- They are still TextButtons with a full-width hit area, just an invisible
-- one. Pretty and untappable is worse than ugly.
local function menuButton(label, sub, col, order, big, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, big and 54 or 46)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Text = ""
	b.LayoutOrder = order
	b.ZIndex = 4
	b.Parent = menu
	local lab = text(b, "[" .. label .. "]", { Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack, TextSize = big and 35 or 28,
		TextColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	local st = Instance.new("UIStroke")
	st.Thickness = 3.4
	st.Color = Color3.fromRGB(34, 40, 36)
	st.Transparency = 0.04
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Parent = lab
	local sc = Instance.new("UIScale")
	sc.Parent = lab
	b.MouseEnter:Connect(function()
		TweenService:Create(lab, TweenInfo.new(0.12), { TextColor3 = col }):Play()
		TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1.08 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(lab, TweenInfo.new(0.16), { TextColor3 = Color3.new(1, 1, 1) }):Play()
		TweenService:Create(sc, TweenInfo.new(0.16), { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onClick)
	return b, lab
end

local hint = text(titleScreen, "", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(0.8, 0, 0, 22),
	Position = UDim2.new(0.5, 0, 1, -16), Font = BODY, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 0.35, ZIndex = 3 })

---------------------------------------------------------------------------
-- MOBILE. Everything above is laid out at a desktop size and scaled, which
-- is the only way a menu this shape survives a 375-wide phone.
---------------------------------------------------------------------------
local scale = Instance.new("UIScale")
scale.Parent = menu
local function relayout()
	local v = camera.ViewportSize
	local s = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.72, 1.15)
	scale.Scale = s
	local narrow = v.X < 700
	barWrap.Size = narrow and UDim2.new(0.9, 0, 0, 68) or UDim2.new(0.62, 0, 0, 74)
	logo.Size = narrow and UDim2.fromScale(0.70, 0.15) or UDim2.fromScale(0.34, 0.22)
	-- PLAY IS PINNED TO THE BOTTOM FURNITURE, NOT TO A FRACTION OF THE SCREEN.
	-- It used to sit at 0.66/0.70 of the height, which is fine in portrait and
	-- collides in landscape: the bar and the tip line are positioned in PIXELS
	-- from the bottom (-34, -122), so on a short viewport -- a phone held
	-- sideways, 667x375 -- they climb to meet a button that is still obediently
	-- two thirds of the way down, and all three land on top of each other.
	-- Measuring from the same edge they do is what makes that impossible.
	playBtn.AnchorPoint = Vector2.new(0.5, 1)
	playBtn.Size = narrow and UDim2.fromOffset(248, 68) or UDim2.fromOffset(300, 78)
	playBtn.Position = narrow and UDim2.new(0.5, 0, 1, -158) or UDim2.new(0.5, 0, 1, -162)
	playLab.TextSize = narrow and 32 or 38
	titleLogo.Size = narrow and UDim2.fromScale(0.68, 0.24) or UDim2.fromScale(0.38, 0.3)
	titleLogo.Position = narrow and UDim2.fromScale(0.5, 0.2) or UDim2.fromScale(0.5, 0.26)
	menu.Position = narrow and UDim2.fromScale(0.5, 0.38) or UDim2.fromScale(0.5, 0.43)
	tip.TextSize = narrow and 14 or 16
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
relayout()

---------------------------------------------------------------------------
-- PHASE 1 RUNNING: rotate the tips, and follow the real progress.
--
-- The bar eases toward the truth rather than snapping to it, and it never
-- goes backwards -- a bar that jumps around reads as broken even when the
-- number behind it is honest.
---------------------------------------------------------------------------
local shown = 0
local tipI = 0
local function nextTip()
	tipI += 1
	tip.Text = TIPS[(tipI - 1) % #TIPS + 1]
end
nextTip()
task.spawn(function()
	while loadScreen.Visible do
		task.wait(4.5)
		if not loadScreen.Visible then break end
		fadeText(tip, TweenInfo.new(0.25), 1)
		task.wait(0.28)
		nextTip()
		fadeText(tip, TweenInfo.new(0.3), 0.1)
	end
end)

---------------------------------------------------------------------------
-- THE BAR IS A PERFORMANCE NOW, AND THIS IS THE DELIBERATE VERSION OF THAT.
--
-- It used to be wired to City.loadProgress(). That was honest, and being
-- honest is exactly why it was replaced: an honest bar is one whose length
-- depends on the player's hardware, so the slowest phone -- the player most
-- likely to leave -- got the longest and least encouraging one, and got told
-- so in percentages the whole way down. This runs the same fifteen seconds
-- for everybody, and PLAY lands the moment it fills.
--
-- WHAT DID NOT CHANGE IS THE SAFETY. The city streams behind this card
-- exactly as before, and the city's own curtain is still underneath waiting
-- for the blocks near you. The bar stopped reporting the wait; it did not
-- remove it.
--
-- THE CURVE HAS TWO STALLS IN IT ON PURPOSE. A bar that climbs at a constant
-- rate reads as a timer, because that is what it is. Real loading lurches, so
-- this one lurches: fast off the line, a pause at 34%, a run, a second pause
-- at 78%, then home. It is also monotonic by construction, which the honest
-- one never quite managed.
---------------------------------------------------------------------------
local BAR_SECS = 14.2
local CURVE = {
	{ 0.0, 0.00 }, { 1.2, 0.18 }, { 2.4, 0.31 }, { 4.0, 0.34 }, { 5.2, 0.52 },
	{ 7.0, 0.61 }, { 9.0, 0.74 }, { 11.0, 0.78 }, { 12.6, 0.90 }, { 13.6, 0.97 },
	{ BAR_SECS, 1.00 },
}
local function curveAt(t)
	if t <= 0 then return 0 end
	for i = 2, #CURVE do
		local a, b = CURVE[i - 1], CURVE[i]
		if t <= b[1] then
			return a[2] + (b[2] - a[2]) * ((t - a[1]) / (b[1] - a[1]))
		end
	end
	return 1
end
local t0 = os.clock()
task.spawn(function()
	while loadScreen.Visible do
		shown = math.max(shown, curveAt(os.clock() - t0))
		fill.Size = UDim2.fromScale(shown, 1)
		pctLabel.Text = math.floor(shown * 100) .. "%"
		if shown >= 1 then
			loadLabel.Text = "READY"
			pctLabel.TextColor3 = C.mintDark
		elseif shown >= 0.78 then loadLabel.Text = "ALMOST THERE"
		elseif shown >= 0.34 then loadLabel.Text = "BUILDING THE CITY"
		else loadLabel.Text = "LOADING ASSETS" end
		task.wait(0.06)
	end
end)

-- and the button, on its own clock, so a stall in the bar loop cannot hold it
task.delay(PLAY_AT, revealPlay)

---------------------------------------------------------------------------
-- ANCHOR THE PLAYER WHILE THE CARD IS UP.
--
-- The card is on screen for fifteen seconds while the city streams in behind
-- it, and for some of that the ground under the spawn does not exist yet.
-- Nobody is looking, so nobody sees the fall -- they just arrive somewhere
-- they did not expect, or under the map. It also settles the drift QA logged
-- against teleported characters.
--
-- Re-asserted on respawn, because a character that appears while this is up
-- arrives unanchored and the flag set on the old one means nothing.
---------------------------------------------------------------------------
local function anchor(on)
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = on end
end
-- THE HOLD HAS ITS OWN FLAG, AND IT IS NOT loadScreen.Visible.
--
-- This was the bug: pick() unanchored and then left the card visible for half
-- a second while it faded. The loop below woke up inside that window, saw a
-- visible card, and anchored the player again -- one tick after the release
-- and with nothing left to ever undo it. The player entered the city
-- permanently frozen, WASD dead, and nothing on screen to explain it.
--
-- A flag that means "still holding" cannot drift from the thing that clears
-- it, and the loop releases on its own way out as a second guarantee.
local holdAnchor = true
task.spawn(function()
	while holdAnchor and loadScreen.Visible do
		anchor(true)
		task.wait(0.5)
	end
	anchor(false)
end)
player.CharacterAdded:Connect(function()
	if holdAnchor then
		task.wait(0.1)
		anchor(holdAnchor)
	end
end)
-- AND A CEILING ON IT. If pick() never runs -- an error, a player who walks
-- away -- the hold must still end. Nothing about this screen is worth leaving
-- somebody unable to move.
task.delay(PLAY_AT + 20, function()
	if holdAnchor then
		warn("[SminskiTitle] failsafe: releasing the anchor hold")
		holdAnchor = false
		anchor(false)
	end
end)

---------------------------------------------------------------------------
-- PHASE 2: THE MENU. The background is a slow orbit around wherever the
-- player is standing in the real city -- so the title screen is the game
-- running, not a picture of it, and it is guaranteed to have streamed
-- geometry in frame because that is exactly what streaming builds around.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- THE FLIGHT. When the plates finish, the camera drops out of the cloud
-- layer and settles over the city, and the menu fades in once it lands.
--
-- THIS IS WHY THERE IS NO VIDEO. Roblox only plays uploaded video assets,
-- and video upload is gated behind account verification and moderation --
-- but a camera move costs nothing, runs at whatever framerate the player's
-- device manages, and cannot be the wrong resolution. It is also the real
-- game rather than a recording of it, so the menu ends up sitting over a
-- city that is actually there.
--
-- IT ORBITS THE PLAYER, NOT DOWNTOWN. Streaming builds blocks around
-- wherever the player is standing, so the one patch of city guaranteed to
-- exist when this runs is the patch they are in. Aiming somewhere prettier
-- would risk flying the hero shot over an empty grid.
---------------------------------------------------------------------------
-- NOT a connection: BindToRenderStep returns nil, so this has to be a plain
-- flag. It was written as `camConn = RunService:BindToRenderStep(...)`, which
-- left camConn nil forever -- so stopCamera()'s `if camConn` never fired, the
-- binding never unbound, and this screen kept writing camera.CFrame every
-- frame for the rest of the session. That is what made the view pan on its
-- own after entering the game, and what made driving impossible: the car
-- camera is scripted too, and this binding runs after it.
local camOn = false
local FLIGHT = 2.6              -- the dive in, and the climb back out
local HIGH_R, HIGH_H = 420, 300 -- the menu pose: floating over the map
local NEAR_R, NEAR_H = 26, 11   -- over the player's shoulder, ready to hand off

local function centreOf()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.Position + Vector3.new(0, 24, 0)) or (workspace.CurrentCamera.CFrame.Position)
end

-- k = 0 is the MENU pose, floating high over the map; k = 1 is over the
-- player's shoulder, where the game's own follow camera takes over. The dive
-- in and the climb back out are the same curve run in opposite directions,
-- which is why leaving the menu and returning to it feel like one movement
-- rather than two effects.
local function poseAt(k, a)
	local e = k * k * (3 - 2 * k)                 -- smoothstep, both ways
	local centre = centreOf()
	local h = HIGH_H + (NEAR_H - HIGH_H) * e
	local r = HIGH_R + (NEAR_R - HIGH_R) * e
	local pos = centre + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
	local look = centre + Vector3.new(0, -10 * e, 0)
	return CFrame.lookAt(pos, look), 70 + (65 - 70) * e
end

-- dir = 0 park at the menu pose; 1 dive in; -1 climb back out
local function startCamera(dir)
	camera.CameraType = Enum.CameraType.Scriptable
	local a = 0.7
	local t = (dir == -1) and FLIGHT or 0
	camOn = true
	RunService:BindToRenderStep("SminskiTitleCam", Enum.RenderPriority.Camera.Value + 10, function(dt)
		if dir == 1 then t = math.min(FLIGHT, t + dt)
		elseif dir == -1 then t = math.max(0, t - dt) end
		-- it keeps turning gently at the menu, so that pose is never a frozen
		-- frame; during a move the drift slows so the move reads clearly
		a += dt * ((dir ~= 0) and 0.02 or 0.035)
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local cf, fov = poseAt(t / FLIGHT, a)
		camera.CFrame = cf
		camera.FieldOfView = fov
	end)
	return function() return (dir == 1 and t >= FLIGHT) or (dir == -1 and t <= 0) or dir == 0 end
end
local function stopCamera()
	-- Belt and braces: unbind by name unconditionally. The flag can get out
	-- of step with reality (a second startCamera, an error mid-flight), and a
	-- stale render binding that owns the camera forever is the single worst
	-- failure this screen can have -- it breaks walking, driving and every
	-- scripted camera in the game.
	camOn = false
	pcall(function() RunService:UnbindFromRenderStep("SminskiTitleCam") end)
end

-- BillboardGuis with AlwaysOnTop draw above ScreenGuis, so the house
-- nameplates punch straight through the title screen. Put them away while the
-- menu is up and give them back on the way out.
local hidden = {}
local function hideWorldLabels(on)
	if on then
		for _, d in workspace:GetDescendants() do
			if d:IsA("BillboardGui") and d.Enabled then
				d.Enabled = false
				table.insert(hidden, d)
			end
		end
	else
		for _, d in hidden do
			if d.Parent then d.Enabled = true end
		end
		table.clear(hidden)
	end
end
-- ONE sweeper, forever. Anything that streams in while the menu is up would
-- pop through it, so the hide is repeated -- but the old version spawned a
-- fresh loop AND a fresh Stop listener on every reopen, so a player who
-- opened the menu ten times had ten of each racing each other.
task.spawn(function()
	while true do
		task.wait(0.6)
		if sweeping then hideWorldLabels(true) end
	end
end)

local function pick(what)
	if picked then return end
	picked = true
	gui:SetAttribute("Done", true)
	titleScreen:SetAttribute("Stop", true)
	sweeping = false
	hideWorldLabels(false)
	choice.Value = what
	-- THE LOADING CARD GOES TOO. PLAY now lives on the card, so the card is
	-- usually the screen that is actually up when this runs -- and the old
	-- version only ever faded titleScreen, which would have left the card
	-- sitting over the game with a live PLAY button on it.
	if loadScreen.Visible then
		holdAnchor = false   -- see ANCHOR THE PLAYER WHILE THE CARD IS UP
		anchor(false)
		playBtn.Visible = false
		logo.Visible = false
		TweenService:Create(loadScreen, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		for _, d in loadScreen:GetDescendants() do
			if d:IsA("TextLabel") then fadeText(d, TweenInfo.new(0.35), 1)
			elseif d:IsA("ImageLabel") then TweenService:Create(d, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
			elseif d:IsA("GuiObject") then TweenService:Create(d, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play() end
		end
		task.delay(0.5, function()
			loadScreen.Visible = false
			for _, d in loadScreen:GetDescendants() do
				if d:IsA("GuiObject") then d.Visible = false end
			end
		end)
	end
	-- THE ZOOM IS THE TRANSITION INTO PLAY. Fly down from the menu pose to
	-- the player's shoulder, and only then hand over to the game's own follow
	-- camera -- so entering the game is one continuous move rather than a cut.
	for _, d in titleScreen:GetDescendants() do
		if d:IsA("TextLabel") then fadeText(d, TweenInfo.new(0.25), 1) end
		if d:IsA("ImageLabel") then TweenService:Create(d, TweenInfo.new(0.25), { ImageTransparency = 1 }):Play() end
	end
	TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	stopCamera()
	local landed = startCamera(1)
	local guard = os.clock()
	while not landed() and os.clock() - guard < FLIGHT + 1 do task.wait(0.03) end
	stopCamera()
	-- HAND THE CAMERA BACK PROPERLY. The city drives the on-foot view with
	-- CameraType.Custom *and* CameraSubject on the humanoid -- Roblox's own
	-- follow camera. Returning the type without the subject leaves that
	-- camera with nothing to follow, so it just sits wherever the flight
	-- parked it and the player starts the game looking at the map.
	local function handBack()
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		if hum then camera.CameraSubject = hum end
		camera.FieldOfView = 70
	end
	handBack()
	task.spawn(function()
		-- The city re-seats the character on entry and that drops whatever
		-- subject was set before it, so keep asserting it until it sticks.
		--
		-- BUT STAND DOWN IF THE GAME TAKES THE CAMERA. Cars, rides and the
		-- lifts all set CameraType.Scriptable on purpose; carrying on
		-- asserting Custom over the top of that is how you end up unable to
		-- drive. Once something else has claimed it, this screen is done.
		for _ = 1, 10 do
			task.wait(0.2)
			if camera.CameraType == Enum.CameraType.Scriptable then return end
			local ch = player.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= hum then
				pcall(handBack)
			end
		end
	end)
	for _, o in { titleScreen, shade } do
		TweenService:Create(o, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	end
	for _, d in titleScreen:GetDescendants() do
		if d:IsA("ImageLabel") then TweenService:Create(d, TweenInfo.new(0.45), { ImageTransparency = 1 }):Play() end
		if d:IsA("TextLabel") then fadeText(d, TweenInfo.new(0.35), 1) end
		if d:IsA("ImageLabel") then TweenService:Create(d, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play() end
		if d:IsA("TextButton") then TweenService:Create(d, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play() end
	end
	hasEntered = true
	if refreshMenuLabels then refreshMenuLabels() end
	playEvent:Fire(what)
	-- HIDDEN, NOT DESTROYED. The player can come back to this menu from the
	-- city HUD, and the climb back out is the dive played in reverse -- which
	-- only works if the screen and its camera rig are still here.
	titleScreen.Visible = false
	loadScreen.Visible = false
	picked = false
end

-- COMING BACK. Fired from the city when the player asks for the menu again:
-- climb out to the menu pose, then fade the title back in on top of it.
local function reopenMenu()
	if titleScreen.Visible then return end
	picked = false
	peeking = false
	-- BUILD IT ON DEMAND. A first join never opens this menu at all now --
	-- PLAY on the loading card goes straight into the city -- so the menu is
	-- built the first time somebody actually asks for it.
	buildMenu()
	if refreshMenuLabels then refreshMenuLabels() end
	sweeping = true
	gui:SetAttribute("Sweeping", true)
	hideWorldLabels(true)
	stopCamera()
	local outAt = startCamera(-1)
	local guard = os.clock()
	while not outAt() and os.clock() - guard < FLIGHT + 1 do task.wait(0.03) end
	stopCamera()
	startCamera(0)
	titleScreen.Visible = true
	shade.BackgroundTransparency = 1
	TweenService:Create(shade, TweenInfo.new(0.5), { BackgroundTransparency = 0.82 }):Play()
	for _, d in titleScreen:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = 1
			local st = d:FindFirstChildWhichIsA("UIStroke")
			if st then st.Transparency = 1 end
			fadeText(d, TweenInfo.new(0.5), 0)
		end
		if d:IsA("ImageLabel") then
			d.ImageTransparency = 1
			TweenService:Create(d, TweenInfo.new(0.5), { ImageTransparency = 0 }):Play()
		end
	end
end
do
	local ev = Instance.new("BindableEvent")
	ev.Name = "SR_ShowMenu"
	ev.Parent = ReplicatedFirst
	ev.Event:Connect(function() task.spawn(reopenMenu) end)
end

-- WHICH OPTIONS ACTUALLY ENTER THE GAME. Only the two that are about being
-- somewhere: starting, and going home. The rest are screens -- opening the
-- shop should not fly you down into the city and leave you standing in it,
-- because you asked for the shop, not for the city. Those open over the menu
-- with the world still drifting behind them.
local ENTERS_GAME = { play = true, home = true }
local peekEvent = Instance.new("BindableEvent")
peekEvent.Name = "SR_Peek"
peekEvent.Parent = ReplicatedFirst
local backEvent = Instance.new("BindableEvent")
backEvent.Name = "SR_MenuBack"
backEvent.Parent = ReplicatedFirst

-- fade the menu furniture without touching the camera, so the world keeps
-- drifting behind whatever screen just opened
local function fadeMenu(out)
	local tw = TweenInfo.new(0.28)
	for _, d in titleScreen:GetDescendants() do
		if d:IsA("TextLabel") then fadeText(d, tw, out and 1 or 0) end
		if d:IsA("ImageLabel") then TweenService:Create(d, tw, { ImageTransparency = out and 1 or 0 }):Play() end
		if d:IsA("TextButton") then d.Active = not out end
	end
	TweenService:Create(shade, tw, { BackgroundTransparency = out and 1 or 0.82 }):Play()
end
local function peek(what)
	if peeking then return end
	peeking = true
	fadeMenu(true)
	peekEvent:Fire(what)
end
backEvent.Event:Connect(function()
	if not peeking then return end
	peeking = false
	fadeMenu(false)
end)

-- STUDIO ONLY: a way in for tests. TextButton.Activated cannot be fired from
-- a script, so without this there is no way to exercise a menu option.
--
-- IT MUST BRANCH THE SAME WAY go() DOES. The first version called pick()
-- unconditionally, which meant every test of WORK, SHOP or SETTINGS dived
-- into the game and "confirmed" a bug that only existed in the test hook --
-- and, worse, could never have caught a real routing mistake, because it was
-- not running the routing. This has to sit below peek() for that reason.
if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "SR_TestPick"
	bf.Parent = ReplicatedFirst
	bf.OnInvoke = function(what)
		what = what or "play"
		if ENTERS_GAME[what] then task.spawn(pick, what) else task.spawn(peek, what) end
		return true
	end
	-- AND A WAY TO SKIP THE FIFTEEN-SECOND WAIT. Without this the only way
	-- to test the button is to sit through its timer on every single run.
	local pf = Instance.new("BindableFunction")
	pf.Name = "SR_TestPlayNow"
	pf.Parent = ReplicatedFirst
	pf.OnInvoke = function()
		revealPlay()
		return playBtn.Visible
	end
end

---------------------------------------------------------------------------
-- THE MENU, BUILT ON DEMAND. It is no longer part of getting into the game:
-- PLAY on the loading card enters directly, which is one press instead of
-- two. This is what you get when you ask for the menu from the city HUD, and
-- on most sessions it is never built at all.
---------------------------------------------------------------------------
buildMenu = function()
	if menuShown then return end
	menuShown = true
	picked = false
	-- MENU OPTIONS ARE REAL DESTINATIONS. Every one of these lands you
	-- somewhere that exists; none of them is a label over nothing. There is
	-- no QUIT because Roblox has no quit -- leaving is the platform's button,
	-- not ours, and a dead menu item is worse than a missing one.
	local function go(what)
		return function()
			if ENTERS_GAME[what] then pick(what) else peek(what) end
		end
	end
	-- START GAME the first time, RESUME every time after: reopening the menu
	-- mid-session and being told to "start" a game you are already playing
	-- reads as though it is about to throw the session away.
	local _, startLab = menuButton("START GAME", nil, C.mint, 1, true, go("play"))
	function refreshMenuLabels()
		startLab.Text = hasEntered and "[RESUME]" or "[START GAME]"
	end
	refreshMenuLabels()
	menuButton("GO TO MY HOUSE", nil, C.sky, 2, false, go("home"))
	menuButton("WORK", nil, C.coral, 3, false, go("work"))
	menuButton("SHOP", nil, C.gold, 4, false, go("shop"))
	menuButton("SETTINGS", nil, Color3.fromRGB(214, 208, 224), 5, false, go("settings"))
	hint.Text = "a cosy city to live in \u{00B7} 30 minutes is a whole day"
	-- the balcony still was the last frame of an intro that no longer runs, so
	-- the menu sits over the live camera instead
	if titleBg then titleBg.Visible = false end
	relayout()
end

-- PLAY IS THE WAY IN. Connected here because pick() has to exist first.
playBtn.Activated:Connect(function()
	if not playBtn.Visible or picked then return end
	task.spawn(pick, "play")
end)

-- if anything above threw, nobody may be left staring at a card with no way
-- off it. The reveal runs on its own task.delay, so this only fires if that
-- task itself was lost.
task.delay(PLAY_AT + 8, function()
	if gui.Parent and loadScreen.Visible and not playBtn.Visible then
		warn("[SminskiTitle] failsafe: showing PLAY")
		pcall(revealPlay)
	end
end)
