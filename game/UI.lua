-- UI: home page, shop (outfits / upgrades / capsules), collection, stats,
-- settings, in-run HUD, revive prompt, results. Soft paper + toy-packaging
-- style with tactile "physical key" buttons.

return function(Config, Models, Audio, ctx)
	local TweenService = game:GetService("TweenService")
	local UIS = game:GetService("UserInputService")

	local UI = {}
	local Art = require(game:GetService("ReplicatedStorage"):WaitForChild("SminskiShared"):WaitForChild("Art"))
	UI.Art = Art

	---------------------------------------------------------------------------
	-- STYLE
	---------------------------------------------------------------------------
	-- THE PIXEL PALETTE (docs/PIXEL_UI.md section 2).
	--
	-- Every intent hue is a PAIR: the light value is the button face, the dark
	-- value is the 8px body underneath it. That pairing is what makes a
	-- control read as a physical key rather than a coloured rectangle, and it
	-- is why `mintDark` stopped being a one-off and became the shape every
	-- colour follows.
	--
	-- WHITE LABELS ON LIGHT FACES FAIL CONTRAST, AND THAT IS HANDLED
	-- ELSEWHERE. White on `mint` is about 2.4:1. The fix is NOT to darken the
	-- faces -- that kills the palette -- it is the 4px ink outline every
	-- button label carries (see `button` below), which is how pixel UI has
	-- always solved this.
	--
	-- The old key names all survive, so nothing written before today moves.
	local C = {
		-- ink
		ink = Color3.fromRGB(46, 51, 40),
		inkSoft = Color3.fromRGB(86, 92, 74),
		inkFaint = Color3.fromRGB(138, 144, 120),
		-- paper
		paper = Color3.fromRGB(253, 246, 227),
		paper2 = Color3.fromRGB(239, 228, 200),
		paper3 = Color3.fromRGB(223, 207, 168),
		hi = Color3.fromRGB(255, 253, 244),
		-- intent, light / dark pairs
		mint = Color3.fromRGB(143, 208, 122), mintDark = Color3.fromRGB(79, 143, 70),
		gold = Color3.fromRGB(245, 196, 78), goldDark = Color3.fromRGB(184, 134, 42),
		coral = Color3.fromRGB(240, 112, 94), coralDark = Color3.fromRGB(168, 63, 48),
		sky = Color3.fromRGB(111, 178, 232), skyDark = Color3.fromRGB(53, 113, 159),
		lav = Color3.fromRGB(183, 155, 232), lavDark = Color3.fromRGB(110, 85, 166),
		rose = Color3.fromRGB(242, 168, 184), roseDark = Color3.fromRGB(196, 103, 124),
		white = Color3.new(1, 1, 1),
	}
	UI.C = C
	local DISPLAY = Enum.Font.FredokaOne
	local BODY = Enum.Font.GothamMedium
	local BOLD = Enum.Font.GothamBold

	---------------------------------------------------------------------------
	-- TOKENS.
	--
	-- C above is eleven raw colours and nothing else, so every call site chose
	-- one by hand and "which green means go" got decided forty times
	-- independently. Several screens use C.mint for confirm, one uses it for a
	-- progress fill, one for a job badge -- each correct locally, incoherent
	-- together.
	--
	-- T is the semantic layer on top. A call site asks for a ROLE (go, money,
	-- alert) and the role is defined exactly once, here. Recolouring the game
	-- becomes eleven lines instead of a search-and-replace across 20 modules.
	--
	-- C IS STILL EXPORTED AND STILL WORKS. This is additive on purpose:
	-- nothing written before today has to move, and new work reads T.
	---------------------------------------------------------------------------
	local T = {
		-- surfaces
		surface = C.paper,
		surfaceSunk = C.paper2,
		surfaceDeep = C.paper2:Lerp(C.ink, 0.12),

		-- ink
		fg = C.ink,
		fgMuted = C.inkSoft,
		fgOnColor = C.white,

		-- INTENT, not hue. What the control DOES picks the colour.
		go = C.mint, -- confirm, start, accept, travel, "yes"
		goDeep = C.mintDark, -- the pressed / repeat state of go
		money = C.gold, -- coins, shop, buy, reward, anything earned
		alert = C.coral, -- stop, leave, expiring, social attention
		info = C.sky, -- navigate, map, phone, neutral system
		special = C.lav, -- work, progression, premium
		neutral = C.paper2, -- secondary, dismiss, "not now"
		chrome = C.rose, -- device chrome: the phone's status bar and headers
		disabled = C.inkFaint, -- label colour on a control that cannot be used

		-- THE DARK HALF OF EVERY INTENT. `body[T.go]` is not expressible in
		-- Lua (colours are not hashable as table keys usefully), so the pairs
		-- are named. A button given `color = T.go` finds its body here.
		body = { go = C.mintDark, money = C.goldDark, alert = C.coralDark,
			info = C.skyDark, special = C.lavDark, chrome = C.roseDark,
			neutral = C.paper3 },

		-- TYPE SCALE. Twelve ad-hoc sizes were in use; these are the seven
		-- steps they collapse to. Nothing new invents an eighth.
		size = { xs = 12, sm = 14, md = 16, lg = 20, xl = 24, xxl = 30, hero = 42 },
		font = { display = DISPLAY, body = BODY, bold = BOLD },

		-- 4px space scale, and the radii the Blender art actually renders
		space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 },
		radius = { sm = 8, md = 14, lg = 20, pill = 999 },

		-- THE ONLY THREE TOUCH SIZES. 44 design-px is a floor, not a target:
		-- at the phone clamp of 0.6 scale a 44px control is ~26 real px, which
		-- is already the smallest thing a thumb hits reliably. Nothing
		-- tappable ships smaller than tap.min.
		tap = { min = 44, std = 56, wide = 64 },
		-- 8, NOT 5. The body under a button face is two 4px rows; at 5 it was
		-- neither one row nor two and never landed on the pixel grid.
		depth = 8, -- how far a button travels when pressed
		border = 4, -- ink frame on large parts; small parts use 2
		shadow = 12, -- drop shadow offset
	}
	UI.T = T

	local function tween(o, t, props, style)
		local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end
	UI.tween = tween

	local function corner(p, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 14)
		c.Parent = p
		return c
	end
	local function stroke(p, th, col, tr)
		local s = Instance.new("UIStroke")
		s.Thickness = th or 2
		s.Color = col or C.ink
		s.Transparency = tr or 0
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = p
		return s
	end
	local function pad(p, px)
		local u = Instance.new("UIPadding")
		u.PaddingLeft = UDim.new(0, px)
		u.PaddingRight = UDim.new(0, px)
		u.PaddingTop = UDim.new(0, px)
		u.PaddingBottom = UDim.new(0, px)
		u.Parent = p
		return u
	end

	local function frame(parent, props)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = C.paper
		for k, v in props or {} do f[k] = v end
		f.Parent = parent
		return f
	end

	local function text(parent, str, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = BODY
		l.TextColor3 = C.ink
		l.TextScaled = false
		l.TextSize = 18
		l.Text = str
		for k, v in props or {} do
			if k ~= "stroke" then l[k] = v end
		end
		if props and props.stroke then
			local s = Instance.new("UIStroke")
			s.Thickness = props.stroke
			s.Color = C.ink
			s.Parent = l
		end
		l.Parent = parent
		return l
	end
	UI.text = text

	-- glossy candy surface (Blender/painted art): a tintable 9-slice base + an
	-- untinted gloss layer. The frame's BackgroundColor3 keeps driving the tint.
	local function skin(obj, kind, sliceScale)
		local a = Art.ui[kind]
		obj.BackgroundTransparency = 1
		for _, c in obj:GetChildren() do
			if c:IsA("UICorner") then c:Destroy() end
		end
		local function img(id, tint)
			local i = Instance.new("ImageLabel")
			i.Name = "Skin"
			i.BackgroundTransparency = 1
			i.Image = id
			i.ImageColor3 = tint
			-------------------------------------------------------------
			-- THE SINGLE MOST IMPORTANT LINE IN THE PIXEL UI.
			--
			-- Roblox defaults to bilinear filtering. A 16px glyph blown up
			-- to 40px comes out soft, and the entire style collapses --
			-- silently, because it looks correct in the design files and
			-- only wrong in game. Nothing else here matters if this is
			-- missing, so when something looks "nearly right but mushy",
			-- check this first.
			-------------------------------------------------------------
			i.ResampleMode = Enum.ResamplerMode.Pixelated
			i.ScaleType = Enum.ScaleType.Slice
			i.SliceCenter = Rect.new(a.corner, math.min(a.corner, a.size.Y / 2 - 1), a.size.X - a.corner, math.max(a.size.Y - a.corner, a.size.Y / 2 + 1))
			-- INTEGER SLICE SCALE. A 1px border in the source at SliceScale
			-- 4 is a 4px border on screen, which is the token. A fractional
			-- scale reintroduces exactly the uneven-edge problem that
			-- quantise() exists to prevent.
			i.SliceScale = sliceScale or T.border
			i.Size = UDim2.fromScale(1, 1)
			i.ZIndex = obj.ZIndex
			i.Parent = obj
			return i
		end
		local base = img(a.base, obj.BackgroundColor3)
		-- GLOSS IS A 3D IDEA AND HAS NO PLACE HERE. The pixel art carries its
		-- own 1px highlight along the top inside edge, so the separate gloss
		-- overlay is dropped -- but only when the art says so, by setting
		-- `gloss = nil`. While an entry still has one, it still renders, so
		-- the two art sets can coexist during the changeover.
		if a.gloss then img(a.gloss, Color3.new(1, 1, 1)) end
		obj:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			base.ImageColor3 = obj.BackgroundColor3
		end)
		return base
	end
	UI.skin = skin

	-- small image icon from the pixel icon set
	local function icon(parent, name, props)
		local i = Instance.new("ImageLabel")
		i.BackgroundTransparency = 1
		i.Image = Art.icons[name] or ""
		-- same reason as UI.skin: a filtered 16px glyph is a smudge. Every
		-- icon size in use is a multiple of 4 so they land on whole pixels at
		-- any quantised scale.
		i.ResampleMode = Enum.ResamplerMode.Pixelated
		i.ScaleType = Enum.ScaleType.Fit
		for k, v in props or {} do i[k] = v end
		i.Parent = parent
		return i
	end
	UI.icon = icon

	-- soft candy card with a drop shadow
	local function card(parent, size, pos, anchor, color)
		local holder = frame(parent, { Size = size, Position = pos, AnchorPoint = anchor or Vector2.zero, BackgroundTransparency = 1 })
		local shadow = frame(holder, { Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 7), BackgroundColor3 = Color3.fromRGB(30, 20, 60), BackgroundTransparency = 0.72 })
		corner(shadow, 24)
		local face = frame(holder, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or C.paper })
		skin(face, "card", 0.42)
		return holder, face
	end
	UI.card = card

	-- tactile candy button: a glossy face that physically presses down onto its base
	local function button(parent, label, opts)
		opts = opts or {}
		local col = opts.color or C.mint
		local size = opts.size or UDim2.fromOffset(200, 56)
		local depth = opts.depth or T.depth
		local kind = opts.pill and "pill" or "key"
		local faceH = size.Y.Offset > 0 and size.Y.Offset - depth or 50
		-- INTEGER, NOT DERIVED FROM A RADIUS. This used to compute a
		-- fractional SliceScale from the corner radius, which put a 3.7px
		-- border on some buttons and 4px on others. Large parts get 4, small
		-- ones 2, and both are whole pixels at every quantised canvas scale.
		local slice = (size.Y.Offset > 0 and size.Y.Offset < T.tap.min) and 2 or T.border
		local holder = frame(parent, { Size = size, Position = opts.pos or UDim2.new(), AnchorPoint = opts.anchor or Vector2.zero, BackgroundTransparency = 1, LayoutOrder = opts.order or 0 })
		-- THE BODY IS A NAMED DARK VALUE WHERE ONE EXISTS. Lerping the face
		-- toward ink produced a muddy, desaturated under-colour; the palette
		-- now ships a hand-picked dark for every intent hue (T.body). The
		-- lerp stays as the fallback for a one-off colour a call site mixed
		-- itself.
		local function bodyOf(c)
			for name, light in { go = C.mint, money = C.gold, alert = C.coral,
				info = C.sky, special = C.lav, chrome = C.rose, neutral = C.paper2 } do
				if light == c then return T.body[name] end
			end
			return c:Lerp(C.ink, 0.4)
		end
		local base = frame(holder, { Size = UDim2.new(1, 0, 1, -depth), Position = UDim2.fromOffset(0, depth), BackgroundColor3 = bodyOf(col) })
		skin(base, kind, slice)
		local art = frame(holder, { Size = UDim2.new(1, 0, 1, -depth), BackgroundColor3 = col })
		skin(art, kind, slice)
		local face = Instance.new("TextButton")
		face.AutoButtonColor = false
		face.Size = UDim2.new(1, 0, 1, -depth)
		face.BackgroundTransparency = 1
		face.Font = opts.font or DISPLAY
		face.TextSize = opts.textSize or 24
		face.TextColor3 = opts.textColor or C.white
		face.Text = label
		face.BorderSizePixel = 0
		-- THE OUTLINE IS THE CONTRAST FIX, AND IT IS NOT OPTIONAL.
		--
		-- White on the light face of an intent hue is about 2.4:1, which
		-- fails. Darkening the faces to pass would flatten the whole palette,
		-- so the label gets a 4px ink outline instead -- which is how pixel
		-- UI has always solved this, and reads as part of the style rather
		-- than as an accessibility patch.
		--
		-- It used to be 2px of a colour lerped off the face, which is a soft
		-- halo, not an outline: it lifted the text off light faces barely and
		-- off dark ones not at all.
		if (opts.textColor or C.white) == C.white then
			local ts = Instance.new("UIStroke")
			ts.Thickness = T.border
			ts.Color = C.ink
			ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			ts.Parent = face
		end
		if opts.icon then
			-- ICON-ONLY IS A DIFFERENT LAYOUT, NOT A NARROWER ONE. The branch
			-- below puts the icon at the left edge and pads the label past it,
			-- which on a square tile with no label leaves the glyph hard against
			-- one side. A tile centres its icon and skips the padding entirely.
			local isz = math.floor(faceH * (opts.iconOnly and 0.74 or 0.86))
			if opts.iconOnly then
				icon(art, opts.icon, { Size = UDim2.fromOffset(isz, isz), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = art.ZIndex + 1 })
			else
				icon(art, opts.icon, { Size = UDim2.fromOffset(isz, isz), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, math.max(2, faceH * 0.08), 0.5, -1), ZIndex = art.ZIndex + 1 })
				local pd = Instance.new("UIPadding")
				pd.PaddingLeft = UDim.new(0, isz * 0.9)
				pd.Parent = face
			end
		end
		face.Parent = holder
		-- no UIScale here any more: nothing scales a button, so the instance
		-- was pure cost on every one of the hundreds the HUD builds
		local enabled = true
		local baseColor = col
		face.MouseEnter:Connect(function()
			if enabled then tween(art, 0.12, { BackgroundColor3 = baseColor:Lerp(C.white, 0.16) }) end
		end)
		face.MouseLeave:Connect(function()
			tween(art, 0.15, { BackgroundColor3 = baseColor, Position = UDim2.new() })
			tween(face, 0.15, { Position = UDim2.new() })
		end)
		-----------------------------------------------------------------
		-- THE PRESS TRAVELS THE FULL DEPTH, AND NOTHING SCALES.
		--
		-- `depth - 1` left a one-pixel sliver of body showing at the bottom
		-- of a pressed key, so it never quite looked seated. The face now
		-- travels the whole 8 and the body collapses under it.
		--
		-- The 0.96 UIScale squash is GONE. Scaling pixel art by an arbitrary
		-- fraction is the same blur that ResampleMode and quantise() exist
		-- to prevent -- and it was doing it on every single tap, on the one
		-- control the player looks at most. The travel alone reads as a
		-- press; the squash was never carrying it.
		-----------------------------------------------------------------
		face.MouseButton1Down:Connect(function()
			if not enabled then return end
			tween(face, 0.06, { Position = UDim2.fromOffset(0, depth) })
			tween(art, 0.06, { Position = UDim2.fromOffset(0, depth) })
			Audio.play("Click", 1.15, 0.8)
		end)
		face.MouseButton1Up:Connect(function()
			tween(face, 0.22, { Position = UDim2.new() }, Enum.EasingStyle.Back)
			tween(art, 0.22, { Position = UDim2.new() }, Enum.EasingStyle.Back)
		end)
		face.Activated:Connect(function()
			if not enabled then
				Audio.play("Click", 0.6, 0.6) -- dull "nope"
				return
			end
			Audio.play("Click", opts.releasePitch or 1.5, 0.5)
			if opts.onClick then opts.onClick() end
		end)
		local api = { holder = holder, face = face, art = art }
		function api.setEnabled(on)
			enabled = on
			-- DISABLED IS A PALETTE STATE, NOT A DIMMED COLOUR. paper2 face
			-- over a paper3 body, label in inkFaint: it still reads as a
			-- physical key, just an inert one. Lerping the live colour toward
			-- grey made a muddy version of the enabled button instead.
			baseColor = on and col or C.paper2
			art.BackgroundColor3 = baseColor
			base.BackgroundColor3 = on and bodyOf(col) or C.paper3
			face.TextColor3 = on and (opts.textColor or C.white) or C.inkFaint
		end
		function api.setColor(c)
			col = c
			baseColor = c
			art.BackgroundColor3 = c
			base.BackgroundColor3 = c:Lerp(C.ink, 0.4)
		end
		function api.setText(t) face.Text = t end
		-- Studio tests drive real buttons; TextButton.Activated cannot be
		-- fired from a script, so the click body is reachable directly
		function api.press() if opts.onClick then opts.onClick() end end
		return api
	end
	UI.button = button

	local function pill(parent, iconName, iconColor, props)
		local f = frame(parent, props)
		f.BackgroundColor3 = C.paper
		local h = f.Size.Y.Offset
		skin(f, "pill", (h / 2) / Art.ui.pill.corner)
		local name = iconName == "◉" and "coin" or iconName
		local isz = math.floor(h * 1.08)
		icon(f, name, { Size = UDim2.fromOffset(isz, isz), Position = UDim2.new(0, -isz * 0.22, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = f.ZIndex + 1 })
		local l = text(f, "0", { Size = UDim2.new(1, -isz * 0.95, 1, 0), Position = UDim2.fromOffset(isz * 0.86, 0), Font = DISPLAY, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = f.ZIndex + 1 })
		return f, l
	end

	local function fmt(n)
		n = math.floor(n + 0.5)
		local s = tostring(n)
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if out:sub(1, 1) == "," then out = out:sub(2) end
		return out
	end
	UI.fmt = fmt

	-- 3D preview of a Sminski in a ViewportFrame
	local function sminskiViewport(parent, charDef, outfitId, pose, props, skinDef)
		local vf = Instance.new("ViewportFrame")
		vf.BackgroundTransparency = 1
		vf.Ambient = Color3.fromRGB(200, 200, 190)
		vf.LightColor = Color3.fromRGB(255, 250, 240)
		vf.LightDirection = Vector3.new(-0.5, -1, -0.8)
		for k, v in props or {} do vf[k] = v end
		local wm = Instance.new("WorldModel")
		wm.Parent = vf
		local rig = Models.buildSminski(wm, 1, charDef, false, outfitId, skinDef)
		Models.poseSminski(rig, CFrame.Angles(0, 0.35, 0), pose or charDef.idle or "idle", 1.3)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 2.9, 7.4), Vector3.new(0, 2.25, 0))
		cam.Parent = vf
		vf.CurrentCamera = cam
		vf.Parent = parent
		return vf, rig
	end
	UI.sminskiViewport = sminskiViewport

	---------------------------------------------------------------------------
	-- ROOT
	---------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "SminskiRunnerUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	UI.gui = gui

	local root = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	-- THE CANVAS IS DERIVED, NOT REMEMBERED.
	--
	-- rescale() below and every UI.fit caller hang off the same ViewportSize
	-- signal, so whoever reads `uiScale.Scale` before rescale has written it gets
	-- the PREVIOUS viewport's scale -- and then divides the NEW viewport by it.
	-- The city phone measured (367 / 0.90625 - 44) / 480 = 0.752 where the right
	-- answer was 1, purely because its handler ran first.
	--
	-- Computing the scale from the viewport makes every answer independent of
	-- callback order. One definition, so the stored scale and the computed one
	-- cannot disagree.
	-- PIXEL ART CANNOT BE SCALED BY AN ARBITRARY FLOAT.
	--
	-- This used to return whatever the viewport divided to -- 0.6, 0.92, 1.03.
	-- Multiply a 4px border by 0.92 and you get 3.68 real pixels, which Roblox
	-- rounds per EDGE: some borders come out 3px and some 4px on the same
	-- button. That unevenness is exactly what makes pixel art look cheap, and
	-- no amount of redrawing the art fixes it.
	--
	-- Snapping to quarters means 4 * s is always a whole number of real
	-- pixels, so two borders on one control can never disagree.
	--
	-- THE CANVAS NOW JUMPS BETWEEN SIZES AS THE WINDOW RESIZES instead of
	-- easing. That is correct for pixel art and every pixel game does it --
	-- it is not a regression to be smoothed back out later.
	local function quantise(k)
		return math.max(0.25, math.floor(k * 4 + 0.5) / 4)
	end
	UI.quantise = quantise
	local function canvasScale(v)
		local minS = 0.5
		local s = math.clamp(math.min(v.X / 1280, v.Y / 760), minS, 1.5)
		return quantise(s)
	end
	-- the design-pixel canvas for the CURRENT viewport: width, height, scale
	local function canvas()
		local v = workspace.CurrentCamera.ViewportSize
		local s = canvasScale(v)
		return v.X / s, v.Y / s, s
	end
	-- root is laid out at 1280x800 "design pixels" then scaled to fit
	local function rescale()
		local cw, ch, s = canvas()
		uiScale.Scale = s
		root.Size = UDim2.fromOffset(cw, ch)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	-- FIT: the most a w x h card can be scaled and still fit the screen.
	-- Phones are held at 0.6 so buttons stay finger-sized, which leaves them a
	-- canvas only ~650 (or on small phones ~530) units tall -- shorter than
	-- the 760 the screens were designed on. Without this, tall cards run off
	-- the top and bottom and cover everything. Never scales UP past 1.
	function UI.fit(w, h, margin)
		local cw, ch = canvas()
		margin = margin or 28
		-- quantised for the same reason canvasScale is: a card scaled by
		-- 0.87 has 3.48px borders
		return quantise(math.min(1, (cw - margin) / w, (ch - margin) / h))
	end
	-- FIT A WHOLE PAGE. A page laid out edge-to-edge on the 1280x760 design
	-- canvas (the home menu) cannot be "fitted" like a card: its pieces are
	-- anchored to all four sides. So the page gets its own scale, and is made
	-- correspondingly larger than the canvas, which keeps every anchor honest
	-- while the contents shrink until the top stack and the bottom stack stop
	-- colliding. Costs a little button size on the smallest phones; buys a
	-- menu you can actually read.
	local fitPages = {}
	function UI.fitPage(f, designW, designH)
		local psc = Instance.new("UIScale")
		psc.Parent = f
		local function apply()
			-- same staleness as UI.fit had; masked today only because this
			-- handler is connected after rescale's, which is not a guarantee
			local cw, ch = canvas()
			local k = quantise(math.min(1, cw / designW, ch / designH))
			psc.Scale = k
			f.Size = UDim2.fromOffset(cw / k, ch / k)
		end
		apply()
		table.insert(fitPages, apply)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		for _, apply in fitPages do apply() end
	end)
	-- is this a small touch screen? (HUDs use it to collapse their panels)
	-- A phone held sideways, or a very short window. NOT simply "has a touch
	-- screen": a tablet has room for the full layout and should get it.
	function UI.compact()
		local v = workspace.CurrentCamera.ViewportSize
		local touch = game:GetService("UserInputService").TouchEnabled
		return v.Y < 520 or (touch and v.Y < 700)
	end

	-- PORTRAIT IS A DIFFERENT QUESTION FROM COMPACT. compact() asks whether
	-- there is room for the full layout. portrait() asks whether the screen is
	-- taller than it is wide, which is what decides whether the HUD's controls
	-- can live in side columns at all or have to collapse into one bottom dock.
	-- A tall phone is both; a short desktop window is compact but not portrait.
	function UI.portrait()
		local v = workspace.CurrentCamera.ViewportSize
		return v.Y > v.X
	end

	---------------------------------------------------------------------------
	-- THE SAFE AREA, IN DESIGN PIXELS.
	--
	-- Every HUD position in this game was a hand-computed constant, which is
	-- why the capsule pill carries twenty lines explaining why it is 120 wide.
	-- Constants only work while the canvas does: they encode one screen.
	--
	-- THE TWO THINGS THAT ARE NOT OURS, and the reason this cannot be a table
	-- of constants:
	--
	--   Roblox's own top bar (chat, leaderboard, the menu chevron) owns the
	--   top-left. It is drawn by the engine at a FIXED REAL SIZE -- it does not
	--   scale with our canvas -- so its height in design pixels is 40/scale,
	--   not 40. At the phone clamp of 0.6 that is 67 design pixels; at a 1.25
	--   desktop it is 32. A single hardcoded clearance is wrong on one of them.
	--
	--   On touch, the thumbstick owns the bottom-left and the jump button the
	--   bottom-right, both also at fixed real sizes. `stick` and `jump` are the
	--   SQUARES they occupy -- corners, not a band across the bottom. That
	--   distinction is worth the words: treating them as a band costs a
	--   landscape phone 380 design pixels of height and pushes the whole HUD
	--   into the top third of the screen, when in fact the middle of the
	--   bottom edge is free all the way down. Callers ask per column.
	--
	-- Everything the HUD places is then arithmetic on these, so the layout is
	-- derived from the screen rather than remembered from one.
	---------------------------------------------------------------------------
	function UI.safe()
		local v = workspace.CurrentCamera.ViewportSize
		local cw, ch, s = canvas()
		local touch = UIS.TouchEnabled
		return {
			w = cw, h = ch, scale = s,
			portrait = v.Y > v.X,
			touch = touch,
			top = 40 / s + 10,
			side = 20,
			bottom = 16,
			-- ...and they are not a fixed 200 either: Roblox scales its touch
			-- controls with the viewport. A flat 200 real px is 24% of a tall
			-- phone's height and 62% of a small landscape one's, which reserved
			-- so much of a 320-tall screen that the HUD had nowhere left to go.
			stick = touch and math.min(200, v.Y * 0.45) / s or 0,
			jump = touch and math.min(140, v.Y * 0.35) / s or 0,
		}
	end

	-- full-screen effect layers (not scaled)
	local fx = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 })
	-- danger vignette: four edge gradients
	local vignette = {}
	for i, spec in {
		{ UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.7, 0), -90 },
		{ UDim2.new(0.25, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.25, 0, 1, 0), UDim2.new(0.75, 0, 0, 0), 180 },
	} do
		local f = frame(fx, { Size = spec[1], Position = spec[2], BackgroundColor3 = Color3.fromRGB(120, 20, 30), BackgroundTransparency = 0 })
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Visible = false
		vignette[i] = f
	end
	-- speed lines (boost)
	local speedLines = {}
	for i = 1, 14 do
		local f = frame(fx, { Size = UDim2.fromOffset(3, 120), BackgroundColor3 = C.white, BackgroundTransparency = 0.5, Visible = false })
		speedLines[i] = { f = f, t = math.random() }
	end
	-- screen flash
	local flash = frame(fx, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.white, BackgroundTransparency = 1 })

	function UI.setDanger(d, t)
		for _, f in vignette do
			f.Visible = d > 0.02
			f.BackgroundTransparency = 1 - math.clamp(d, 0, 1) * (0.7 + math.sin(t * 7) * 0.15)
		end
	end

	function UI.setSpeedLines(on, dt)
		local v = workspace.CurrentCamera.ViewportSize
		for _, s in speedLines do
			s.f.Visible = on
			if on then
				s.t += dt * 2.5
				if s.t > 1 then
					s.t = 0
					s.x = math.random() < 0.5 and math.random() * 0.25 or 0.75 + math.random() * 0.25
				end
				local x = s.x or 0.1
				s.f.Position = UDim2.fromScale(x, -0.2 + s.t * 1.4)
				s.f.BackgroundTransparency = 0.4 + s.t * 0.6
				s.f.Size = UDim2.fromOffset(2, v.Y * 0.12)
			end
		end
	end

	function UI.flash(color, amount)
		flash.BackgroundColor3 = color or C.white
		flash.BackgroundTransparency = 1 - (amount or 0.5)
		tween(flash, 0.35, { BackgroundTransparency = 1 })
	end

	---------------------------------------------------------------------------
	-- HUD
	---------------------------------------------------------------------------
	local hud = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	UI.hud = hud
	local coinPill, coinLabel = pill(hud, "◉", C.gold, { Size = UDim2.fromOffset(170, 48), Position = UDim2.fromOffset(24, 22) })
	local coinScale = Instance.new("UIScale")
	coinScale.Parent = coinPill
	local distLabel = text(hud, "0m", { Size = UDim2.fromOffset(200, 26), Position = UDim2.fromOffset(30, 76), Font = DISPLAY, TextSize = 22, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, stroke = 2 })

	local scoreLabel = text(hud, "0", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(360, 56), Position = UDim2.new(1, -26, 0, 16), Font = DISPLAY, TextSize = 54, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Right, stroke = 3 })
	local bestLabel = text(hud, "BEST 0", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(300, 22), Position = UDim2.new(1, -28, 0, 72), Font = DISPLAY, TextSize = 18, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Right, stroke = 2 })

	local comboHolder = frame(hud, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(150, 44), Position = UDim2.new(1, -26, 0, 102), BackgroundColor3 = C.paper })
	corner(comboHolder, 22)
	local comboStroke = stroke(comboHolder, 2, C.ink, 0.1)
	local comboLabel = text(comboHolder, "COMBO x1", { Size = UDim2.fromScale(1, 1), Font = DISPLAY, TextSize = 22 })
	local comboScale = Instance.new("UIScale")
	comboScale.Parent = comboHolder
	local comboBar = frame(comboHolder, { Size = UDim2.new(0, 0, 0, 4), Position = UDim2.new(0, 14, 1, -8), BackgroundColor3 = C.mint })
	corner(comboBar, 2)

	local dangerLabel = text(hud, "THE KID IS CLOSE!", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(600, 44), Position = UDim2.new(0.5, 0, 0, 22), Font = DISPLAY, TextSize = 36, TextColor3 = C.coral, stroke = 3, Visible = false })
	local chaseBar = frame(hud, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(260, 12), Position = UDim2.new(0.5, 0, 0, 70), BackgroundColor3 = C.paper })
	corner(chaseBar, 6)
	stroke(chaseBar, 2, C.ink, 0.1)
	local chaseFill = frame(chaseBar, { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.mint })
	corner(chaseFill, 6)
	-- MENU: tap twice to leave the run and go back to the lobby (solo or multiplayer)
	do
		local armed = 0
		local menuBtn
		menuBtn = button(hud, "MENU", { size = UDim2.fromOffset(136, 48), pos = UDim2.new(0, 24, 1, -24), anchor = Vector2.new(0, 1), color = C.paper2, textColor = C.ink, textSize = 19, icon = "house", onClick = function()
			if os.clock() < armed then
				armed = 0
				menuBtn.setText("MENU")
				menuBtn.setColor(C.paper2)
				ctx.leaveRun()
			else
				armed = os.clock() + 3
				menuBtn.setText("LEAVE RUN?")
				menuBtn.setColor(C.coral)
				task.delay(3, function()
					if os.clock() >= armed then
						menuBtn.setText("MENU")
						menuBtn.setColor(C.paper2)
					end
				end)
			end
		end })
		UI.runMenuBtn = menuBtn
	end

	-- chaos meter: five pips + tier name under the chase bar (solo runs)
	local chaosHolder = frame(hud, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(260, 26), Position = UDim2.new(0.5, 0, 0, 86), BackgroundTransparency = 1, Visible = false })
	local chaosPips = {}
	for i = 1, 5 do
		local p = frame(chaosHolder, { Size = UDim2.fromOffset(40, 8), Position = UDim2.fromOffset((i - 1) * 46 + 20, 0), BackgroundColor3 = C.paper })
		corner(p, 4)
		chaosPips[i] = p
	end
	local chaosName = text(chaosHolder, "", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 10), Font = DISPLAY, TextSize = 13, TextColor3 = C.white, stroke = 2 })
	local lastChaos = 0
	function UI.setChaos(tier, runTime)
		chaosHolder.Visible = tier > 0
		if tier <= 0 then lastChaos = 0 return end
		local def = Config.RunTiers[tier]
		local nxt = Config.RunTiers[tier + 1]
		local k = nxt and math.clamp((runTime - def.t) / (nxt.t - def.t), 0, 1) or 1
		for i, p in chaosPips do
			local col = ({ C.mint, C.sky, C.gold, C.coral, Color3.fromRGB(255, 90, 140) })[i]
			if i < tier then
				p.BackgroundColor3 = col
				p.Size = UDim2.fromOffset(40, 8)
			elseif i == tier then
				p.BackgroundColor3 = col
				p.Size = UDim2.fromOffset(math.max(6, 40 * k), 8)
			else
				p.BackgroundColor3 = C.paper
				p.Size = UDim2.fromOffset(40, 8)
			end
		end
		chaosName.Text = "CHAOS " .. tier .. "  ·  " .. def.name
		if tier ~= lastChaos then
			lastChaos = tier
			local sc = chaosHolder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", chaosHolder)
			sc.Scale = 1.35
			tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	local heartsLabel = frame(hud, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(300, 52), Position = UDim2.new(0.5, 0, 0, 58), BackgroundTransparency = 1, Visible = false })
	do
		local hl = Instance.new("UIListLayout")
		hl.FillDirection = Enum.FillDirection.Horizontal
		hl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		hl.Padding = UDim.new(0, 2)
		hl.Parent = heartsLabel
		for i = 1, 5 do
			icon(heartsLabel, "heart", { Name = "H" .. i, Size = UDim2.fromOffset(52, 52), LayoutOrder = i })
		end
	end
	local kidIcon = text(chaseBar, "🧒", { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, -4, 0.5, 0), TextSize = 22 })

	local banner = text(hud, "", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(700, 40), Position = UDim2.new(0.5, 0, 0, 96), Font = DISPLAY, TextSize = 30, TextColor3 = C.gold, stroke = 3, TextTransparency = 1 })
	banner:FindFirstChildOfClass("UIStroke").Transparency = 1

	-- powerup timers
	local puList = frame(hud, { Size = UDim2.fromOffset(210, 300), Position = UDim2.new(0, 24, 0, 120), BackgroundTransparency = 1 })
	local puLayout = Instance.new("UIListLayout")
	puLayout.Padding = UDim.new(0, 8)
	puLayout.Parent = puList
	local puRows = {}
	for i, id in Config.PowerupOrder do
		local def = Config.Powerups[id]
		local row = frame(puList, { Size = UDim2.fromOffset(200, 40), BackgroundColor3 = C.paper, Visible = false, LayoutOrder = i })
		skin(row, "pill", 20 / Art.ui.pill.corner)
		icon(row, Art.powerup[id], { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, -2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = row.ZIndex + 1 })
		text(row, def.name, { Size = UDim2.new(1, -46, 0, 18), Position = UDim2.fromOffset(42, 3), Font = DISPLAY, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left })
		local barBg = frame(row, { Size = UDim2.new(1, -54, 0, 8), Position = UDim2.fromOffset(42, 24), BackgroundColor3 = C.paper2 })
		corner(barBg, 4)
		local bar = frame(barBg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = def.color })
		corner(bar, 4)
		puRows[id] = { row = row, bar = bar }
	end

	-- centre pop text (near miss / perfect / +25)
	local popLayer = frame(hud, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	function UI.popText(str, color, size, yOff)
		local l = text(popLayer, str, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(500, 50), Position = UDim2.new(0.5, math.random(-40, 40), 0.36, yOff or 0), Font = DISPLAY, TextSize = size or 34, TextColor3 = color or C.white, stroke = 3 })
		local sc = Instance.new("UIScale")
		sc.Scale = 0.4
		sc.Parent = l
		tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(0.45, function()
			tween(l, 0.4, { Position = l.Position - UDim2.fromOffset(0, 40), TextTransparency = 1 })
			local st = l:FindFirstChildOfClass("UIStroke")
			if st then tween(st, 0.4, { Transparency = 1 }) end
			task.delay(0.45, function() l:Destroy() end)
		end)
	end

	function UI.banner(str, color, hold)
		banner.Text = str
		banner.TextColor3 = color or C.gold
		banner.TextTransparency = 0
		local st = banner:FindFirstChildOfClass("UIStroke")
		st.Transparency = 0
		local sc = banner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", banner)
		sc.Scale = 0.6
		tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(hold or 1.6, function()
			if banner.Text == str then
				tween(banner, 0.5, { TextTransparency = 1 })
				tween(st, 0.5, { Transparency = 1 })
			end
		end)
	end

	function UI.coinBump(amount)
		coinScale.Scale = 1.12
		tween(coinScale, 0.18, { Scale = 1 })
		if amount and amount > 1 then
			UI.popText("+" .. amount, C.gold, 24, 60)
		end
	end

	local lastMult = 1
	function UI.updateHud(s)
		coinLabel.Text = fmt(s.coins)
		scoreLabel.Text = fmt(s.score)
		distLabel.Text = fmt(s.distance / Config.StudsPerMeter) .. "m"
		bestLabel.Text = "BEST " .. fmt(math.max(s.best, s.score))
		comboLabel.Text = "COMBO x" .. s.mult
		local steps = Config.ComboSteps
		local cur, nxt = steps[s.mult] or 0, steps[s.mult + 1]
		comboBar.Size = UDim2.new(nxt and math.clamp((s.comboPts - cur) / (nxt - cur), 0, 1) or 1, -28, 0, 4)
		if s.mult ~= lastMult then
			local up = s.mult > lastMult
			lastMult = s.mult
			local col = up and ({ C.paper, C.mint, C.sky, C.lav, C.gold, C.coral, C.coral, C.coral })[s.mult] or C.paper
			comboHolder.BackgroundColor3 = col
			comboLabel.TextColor3 = s.mult >= 2 and C.white or C.ink
			comboScale.Scale = up and 1.3 or 0.85
			tween(comboScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			comboStroke.Thickness = 2 + math.min(s.mult, 5) * 0.4
		end
		-- hearts mode (no chaser) vs chase meter
		heartsLabel.Visible = s.hearts ~= nil
		chaseBar.Visible = s.hearts == nil
		if s.hearts then
			for i = 1, 5 do
				local h = heartsLabel["H" .. i]
				h.Visible = i <= (s.maxHearts or 3)
				h.ImageColor3 = i <= s.hearts and C.white or Color3.fromRGB(90, 80, 110)
				h.ImageTransparency = i <= s.hearts and 0 or 0.45
			end
		end
		kidIcon.Text = s.chaser == "dog" and "🐶" or "🧒"
		-- chase meter: chaser icon + fill
		local chase = math.clamp(s.chase / 100, 0, 1)
		chaseFill.Size = UDim2.fromScale(chase, 1)
		chaseFill.BackgroundColor3 = chase < 0.4 and C.coral or chase < 0.7 and C.gold or C.mint
		dangerLabel.Visible = s.hearts == nil and s.chase < Config.Chase.DangerAt
		dangerLabel.Text = s.chaser == "dog" and "THE DOG IS RIGHT BEHIND YOU!" or "THE KID IS CLOSE!"
		dangerLabel.TextTransparency = 0.15 + math.sin(s.t * 12) * 0.15
		if UI._squadData then
			for i, r in UI._squadRows do
				local m = UI._squadData[i]
				r.row.Visible = m ~= nil
				if m then
					r.name.Text = m.name
					r.dot.BackgroundColor3 = Config.RankTier(1000).color
					for _, tr in Config.RankTiers do if tr.id == m.tier then r.dot.BackgroundColor3 = tr.color end end
					if m.left then
						r.status.Text = "left"
						r.status.TextColor3 = C.inkSoft
					elseif m.down then
						r.status.Text = m.respawnAt and string.format("%.0fs", math.max(0, m.respawnAt - workspace:GetServerTimeNow())) or "down"
						r.status.TextColor3 = C.coral
					else
						r.status.Text = "running"
						r.status.TextColor3 = C.mintDark
					end
				end
			end
		end
		for id, r in puRows do
			local p = s.powerups[id]
			r.row.Visible = p ~= nil and p.left > 0
			if p and p.left > 0 then
				r.bar.Size = UDim2.fromScale(p.left / p.total, 1)
			end
		end
	end

	-- 3-2-1-GO countdown
	local countLabel = text(root, "", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(400, 160), Position = UDim2.fromScale(0.5, 0.42), Font = DISPLAY, TextSize = 130, TextColor3 = C.white, stroke = 6, Visible = false })
	local countScale = Instance.new("UIScale")
	countScale.Parent = countLabel
	function UI.countdown(str, color)
		countLabel.Visible = str ~= nil
		if not str then return end
		countLabel.Text = str
		countLabel.TextColor3 = color or C.white
		countLabel.TextTransparency = 0
		countScale.Scale = 1.6
		tween(countScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	local caughtLabel = text(root, "CAUGHT!", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(700, 140), Position = UDim2.fromScale(0.5, 0.3), Font = DISPLAY, TextSize = 110, TextColor3 = C.coral, stroke = 6, Visible = false, Rotation = -6 })
	local caughtScale = Instance.new("UIScale")
	caughtScale.Parent = caughtLabel
	function UI.caught(on, label)
		caughtLabel.Visible = on
		if label then caughtLabel.Text = label end
		if on then
			caughtScale.Scale = 2.2
			tween(caughtScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	---------------------------------------------------------------------------
	-- HOME PAGE
	---------------------------------------------------------------------------
	local home = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	UI.home = home
	-- left column + centre buttons + right column need ~1200 across, and the
	-- top stack (to y=366) plus the bottom stack (from -246) need ~720 down
	UI.fitPage(home, 1200, 720)

	-- title
	local title = icon(home, "", { Image = Art.logo, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(410, 216), Position = UDim2.new(0.5, 0, 0, 4) })
	text(home, "a tiny toy is on the run", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(500, 26), Position = UDim2.new(0.5, 0, 0, 214), Font = DISPLAY, TextSize = 22, TextColor3 = C.white, stroke = 2 })

	-- profile card (top-left): level + xp + name
	local profHolder, prof = card(home, UDim2.fromOffset(300, 92), UDim2.fromOffset(24, 22))
	local lvlBadge = frame(prof, { Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.mint })
	corner(lvlBadge, 32)
	stroke(lvlBadge, 2, C.mintDark)
	text(lvlBadge, "LV", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 9), Font = DISPLAY, TextSize = 14, TextColor3 = C.white })
	local lvlLabel = text(lvlBadge, "1", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 24), Font = DISPLAY, TextSize = 30, TextColor3 = C.white })
	local nameLabel = text(prof, "player", { Size = UDim2.new(1, -100, 0, 24), Position = UDim2.fromOffset(90, 16), Font = DISPLAY, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local xpBg = frame(prof, { Size = UDim2.new(1, -106, 0, 12), Position = UDim2.fromOffset(90, 46), BackgroundColor3 = C.paper2 })
	corner(xpBg, 6)
	stroke(xpBg, 1.5, C.ink, 0.3)
	local xpFill = frame(xpBg, { Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = C.mint })
	corner(xpFill, 6)
	local xpLabel = text(prof, "0 / 100 xp", { Size = UDim2.new(1, -106, 0, 16), Position = UDim2.fromOffset(90, 62), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })

	-- currency (top-right)
	local homeCoinPill, homeCoins = pill(home, "◉", C.gold, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(190, 52), Position = UDim2.new(1, -24, 0, 26) })

	-- best-run card (right)
	local bestHolder, bestCard = card(home, UDim2.fromOffset(250, 150), UDim2.new(1, -24, 0, 100), Vector2.new(1, 0))
	text(bestCard, "BEST RUN", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 14), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })
	local bestScoreLabel = text(bestCard, "0", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 40), Font = DISPLAY, TextSize = 42 })
	local bestDistLabel = text(bestCard, "0m", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 88), Font = BOLD, TextSize = 18, TextColor3 = C.inkSoft })
	local runsLabel = text(bestCard, "0 runs", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 114), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft })

	-- wearing card (left)
	local rankHolder, rankCard = card(home, UDim2.fromOffset(300, 58), UDim2.fromOffset(24, 128))
	local rankChip = frame(rankCard, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.mint })
	corner(rankChip, 17)
	stroke(rankChip, 2, C.ink, 0.2)
	local rankName = text(rankCard, "Glow", { Size = UDim2.new(1, -70, 0, 24), Position = UDim2.fromOffset(58, 7), Font = DISPLAY, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
	local rankElo = text(rankCard, "1000 rating", { Size = UDim2.new(1, -70, 0, 16), Position = UDim2.fromOffset(58, 32), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
	local wearHolder, wearCard = card(home, UDim2.fromOffset(250, 96), UDim2.fromOffset(24, 200))
	text(wearCard, "WEARING", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 12), Font = DISPLAY, TextSize = 16, TextColor3 = C.inkSoft })
	local wearChar = text(wearCard, "Glow", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 32), Font = DISPLAY, TextSize = 28 })
	do
		local giftBtn = button(home, "DAILY GIFT", { size = UDim2.fromOffset(250, 58), pos = UDim2.fromOffset(24, 308), color = C.coral, textSize = 20, icon = "star", onClick = function() UI.open("daily") end })
		local dot = frame(giftBtn.holder, { Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -8, 0, -4), BackgroundColor3 = C.gold, ZIndex = 8 })
		corner(dot, 9)
		stroke(dot, 2, C.white, 0)
		UI._giftBtn = { btn = giftBtn, dot = dot }
	end
	local wearOutfit = text(wearCard, "no outfit", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 64), Font = BODY, TextSize = 15, TextColor3 = C.inkSoft })

	button(home, "EXPLORE THE TABLE  ▸", { size = UDim2.fromOffset(300, 54), pos = UDim2.new(0.5, 0, 0, 250), anchor = Vector2.new(0.5, 0), color = C.mint, textSize = 22, pill = true, icon = "house", onClick = function() if ctx.explore then ctx.explore() end end })
	local startBtn = button(home, "RUN SOLO", { size = UDim2.fromOffset(300, 84), pos = UDim2.new(0.5, -160, 1, -150), anchor = Vector2.new(0.5, 0.5), textSize = 36, depth = 7, radius = 24, icon = "play", onClick = function() ctx.startRun() end })
	local mapBtn = button(home, "MAP: THE BIG HOUSE", { size = UDim2.fromOffset(320, 48), pos = UDim2.new(0.5, -160, 1, -222), anchor = Vector2.new(0.5, 0.5), color = C.paper, textColor = C.ink, textSize = 20, depth = 4, onClick = function() UI.open("maps") end })
	local togetherBtn = button(home, "TOGETHER", { size = UDim2.fromOffset(300, 84), pos = UDim2.new(0.5, 160, 1, -150), anchor = Vector2.new(0.5, 0.5), color = C.sky, textSize = 32, depth = 7, radius = 24, icon = "friends", onClick = function() UI.open("multi") end })
	local navRow = frame(home, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(800, 64), Position = UDim2.new(0.5, 0, 1, -30), BackgroundTransparency = 1 })
	local navLayout = Instance.new("UIListLayout")
	navLayout.FillDirection = Enum.FillDirection.Horizontal
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	navLayout.Padding = UDim.new(0, 14)
	navLayout.Parent = navRow
	local navDefs = {
		{ "SHOP", C.gold, function() UI.open("shop") end, "bag" },
		{ "COLLECTION", C.sky, function() UI.open("collection") end, "capsule" },
		{ "STATS", C.lav, function() UI.open("stats") end, "chart" },
		{ "GOALS", C.coral, function() UI.open("challenges") end, "star" },
		{ "SETTINGS", C.paper2, function() UI.open("settings") end, "gear" },
	}
	for i, d in navDefs do
		button(navRow, d[1], { size = UDim2.fromOffset(i == 2 and 196 or 154, 60), color = d[2], textSize = 19, order = i, icon = d[4], textColor = d[2] == C.paper2 and C.ink or C.white, onClick = d[3] })
	end
	local saveNote = text(home, "", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(700, 18), Position = UDim2.new(0.5, 0, 1, -6), Font = BODY, TextSize = 13, TextColor3 = C.white, stroke = 1 })

	---------------------------------------------------------------------------
	-- MODAL SCREENS
	---------------------------------------------------------------------------
	local modalLayer = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.ink, BackgroundTransparency = 1, Visible = false, Active = true })
	local screens = {}

	local function modal(name, titleText, w, h)
		local holder, face = card(modalLayer, UDim2.fromOffset(w or 860, h or 560), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
		holder.Visible = false
		text(face, titleText, { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 14), Font = DISPLAY, TextSize = 40 })
		button(face, "X", { size = UDim2.fromOffset(48, 50), pos = UDim2.new(1, -16, 0, 16), anchor = Vector2.new(1, 0), color = C.coral, textSize = 24, releasePitch = 0.9, onClick = function() UI.open(nil) end })
		-- back to the previous screen (only shown when there is one)
		local back = button(face, "◀ BACK", { size = UDim2.fromOffset(120, 50), pos = UDim2.fromOffset(16, 16), color = C.paper2, textColor = C.ink, textSize = 20, releasePitch = 0.9, onClick = function() UI.back() end })
		back.holder.Visible = false
		local body = frame(face, { Size = UDim2.new(1, -40, 1, -90), Position = UDim2.fromOffset(20, 76), BackgroundTransparency = 1 })
		local sc = Instance.new("UIScale")
		sc.Parent = holder
		screens[name] = { holder = holder, face = face, body = body, scale = sc, back = face:FindFirstChild("Frame"), w = w or 860, h = h or 560 }
		return body, face
	end

	local refreshers = {}
	local currentScreen
	local history = {} -- screens you came from (BACK / Backspace / B button)
	local goingBack = false
	function UI.open(name)
		if not name and not currentScreen then
			modalLayer.Visible = false
			table.clear(history)
			return
		end
		if currentScreen and screens[currentScreen] then
			screens[currentScreen].holder.Visible = false
			if name and name ~= currentScreen and not goingBack then
				table.insert(history, currentScreen)
			end
		end
		currentScreen = name
		if not name then
			table.clear(history)
			modalLayer.Visible = false
			Audio.play("Whoosh", 0.9, 0.6)
			if UI.onClosed then UI.onClosed() end
			return
		end
		-- an unknown screen name (a dev hook, a typo) used to throw right here,
		-- on screens[name].face, before UI.fit was ever reached
		if not screens[name] then currentScreen = nil modalLayer.Visible = false return end
		for _, child in screens[name].face:GetChildren() do
			local label = child:FindFirstChildWhichIsA("TextButton", true)
			if label and label.Text == "◀ BACK" then child.Visible = #history > 0 end
		end
		modalLayer.Visible = true
		modalLayer.BackgroundTransparency = 1
		tween(modalLayer, 0.2, { BackgroundTransparency = 0.55 })
		local s = screens[name]
		s.holder.Visible = true
		local fit = UI.fit(s.w, s.h)
		s.scale.Scale = 0.85 * fit
		tween(s.scale, 0.28, { Scale = fit }, Enum.EasingStyle.Back)
		Audio.play("Whoosh", 1.2, 0.6)
		if refreshers[name] then refreshers[name]() end
	end

	-- one step back through the screens you opened (or close the last one)
	function UI.back()
		if not currentScreen then return false end
		local prev = table.remove(history)
		goingBack = true
		UI.open(prev)
		goingBack = false
		return true
	end
	function UI.current()
		return currentScreen
	end
	UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.ButtonB then
			UI.back()
		end
	end)

	local function toast(str, color)
		UI.popText(str, color or C.coral, 26, -120)
	end
	UI.toast = toast

	local function scroller(parent, cellSize, padPx)
		local sf = Instance.new("ScrollingFrame")
		sf.Size = UDim2.fromScale(1, 1)
		sf.BackgroundTransparency = 1
		sf.BorderSizePixel = 0
		sf.ScrollBarThickness = 6
		sf.ScrollBarImageColor3 = C.inkSoft
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.CanvasSize = UDim2.new()
		sf.Parent = parent
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = cellSize
		grid.CellPadding = UDim2.fromOffset(padPx or 14, padPx or 14)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = sf
		pad(sf, 6)
		return sf
	end

	---------------------------------------------------------------------------
	-- SHOP
	---------------------------------------------------------------------------
	do
		local shopBody = modal("shop", "TOY SHOP", 900, 590)
		local tabRow = frame(shopBody, { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 })
		local tabLayout = Instance.new("UIListLayout")
		tabLayout.FillDirection = Enum.FillDirection.Horizontal
		tabLayout.Padding = UDim.new(0, 10)
		tabLayout.Parent = tabRow
		local tabPages = {}
		local tabButtons = {}
		local function showTab(id)
			for k, pg in tabPages do pg.Visible = k == id end
			for k, b in tabButtons do b.setColor(k == id and C.mint or C.paper2) ; b.face.TextColor3 = k == id and C.white or C.ink end
		end
		for i, t in { { "skins", "SKINS" }, { "outfits", "HATS" }, { "upgrades", "UPGRADES" }, { "capsules", "CAPSULES" }, { "passes", "PASSES" }, { "coins", "COINS" } } do
			tabButtons[t[1]] = button(tabRow, t[2], { size = UDim2.fromOffset(t[1] == "coins" and 116 or 132, 48), color = C.paper2, textColor = C.ink, textSize = 18, order = i, onClick = function() showTab(t[1]) end })
			local pg = frame(shopBody, { Size = UDim2.new(1, 0, 1, -62), Position = UDim2.fromOffset(0, 62), BackgroundTransparency = 1, Visible = false })
			tabPages[t[1]] = pg
		end

		-- PASSES tab (Robux game passes)
		local passCards = {}
		do
			local grid = scroller(tabPages.passes, UDim2.fromOffset(424, 214), 16)
			for i, p in Config.Passes do
				local f = frame(grid, { BackgroundColor3 = C.white, LayoutOrder = i })
				corner(f, 18)
				local st = stroke(f, 2, C.ink, 0.15)
				local badge = frame(f, { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = p.color })
				corner(badge, 20)
				icon(badge, p.icon, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(10, 10) })
				text(f, p.name, { Size = UDim2.new(1, -120, 0, 30), Position = UDim2.fromOffset(110, 14), Font = DISPLAY, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left })
				for k, perk in p.perks do
					text(f, "•  " .. perk, { Size = UDim2.new(1, -124, 0, 18), Position = UDim2.fromOffset(112, 28 + k * 20), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
				end
				local b = button(f, "", { size = UDim2.new(1, -28, 0, 52), pos = UDim2.new(0.5, 0, 1, -12), anchor = Vector2.new(0.5, 1), textSize = 22, color = p.color, onClick = function() ctx.buyPass(p.id) end })
				passCards[p.id] = { btn = b, stroke = st, def = p }
			end
		end
		local function refreshPasses()
			local owned = ctx.data.Passes or {}
			for id, c in passCards do
				if owned[id] then
					c.btn.setText("OWNED  ✓")
					c.btn.setColor(C.mintDark)
					c.stroke.Color = C.mintDark
					c.stroke.Thickness = 4
				elseif c.def.gamePassId then
					c.btn.setText("R$ " .. fmt(c.def.robux))
					c.btn.setColor(c.def.color)
				else
					c.btn.setText("COMING SOON")
					c.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
				end
			end
		end

		-- SKINS tab. The whole-body look, previewed on whichever capsule
		-- character you have equipped -- so you see the thing you would
		-- actually be wearing, not a stock green Sminski in a costume.
		local skinGrid = scroller(tabPages.skins, UDim2.fromOffset(196, 254))
		local skinCards = {}
		local function buildSkinCards(data)
			for _, c in skinCards do c.frame:Destroy() end
			table.clear(skinCards)
			local charDef = Config.Character(data.EquippedCharacter)
			for i, k in Config.Skins do
				local f = frame(skinGrid, { BackgroundColor3 = C.white, LayoutOrder = i })
				corner(f, 16)
				local st = stroke(f, 2, C.ink, 0.15)
				local bg = frame(f, { Size = UDim2.new(1, -16, 0, 132), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = C.paper2 })
				corner(bg, 12)
				sminskiViewport(bg, charDef, nil, "idle", { Size = UDim2.fromScale(1, 1) }, k)
				text(f, k.name, { Size = UDim2.new(1, -10, 0, 24), Position = UDim2.fromOffset(5, 144), Font = DISPLAY, TextSize = 19 })
				text(f, k.desc or "", { Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 168), Font = BODY, TextSize = 12, TextColor3 = C.inkSoft, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
				local b = button(f, "", { size = UDim2.new(1, -24, 0, 50), pos = UDim2.new(0.5, 0, 1, -10), anchor = Vector2.new(0.5, 1), textSize = 20 })
				skinCards[k.id] = { frame = f, btn = b, stroke = st, def = k }
				b.face.Activated:Connect(function()
					local d = ctx.data
					if (d.OwnedSkins or {})[k.id] then
						if d.EquippedSkin ~= k.id then ctx.equipSkin(k.id) end
					else
						ctx.buySkin(k.id)
					end
				end)
			end
		end
		local skinCharBuilt
		local function refreshSkins()
			local d = ctx.data
			if skinCharBuilt ~= d.EquippedCharacter then
				skinCharBuilt = d.EquippedCharacter
				buildSkinCards(d)
			end
			local owned = d.OwnedSkins or {}
			for id, c in skinCards do
				local equipped = (d.EquippedSkin or "none") == id
				c.stroke.Color = equipped and C.mintDark or C.ink
				c.stroke.Thickness = equipped and 4 or 2
				if equipped then
					c.btn.setText("WEARING")
					c.btn.setColor(C.mintDark)
				elseif owned[id] then
					c.btn.setText("WEAR")
					c.btn.setColor(C.sky)
				elseif c.def.level and (d.Level or 1) < c.def.level then
					c.btn.setText("LEVEL " .. c.def.level)
					c.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
				else
					c.btn.setText("◉ " .. fmt(c.def.price))
					c.btn.setColor(d.Coins >= c.def.price and C.gold or C.paper2:Lerp(C.inkSoft, 0.3))
				end
			end
		end

		-- COINS tab. Robux -> coins, plus the boosts and skips. Anything whose
		-- productId is still 0 is HIDDEN: those ids come from the creator
		-- dashboard, and prompting a purchase for asset 0 fails in the
		-- player's face, so an unfilled entry shows nothing at all.
		do
			local list = Instance.new("ScrollingFrame")
			list.Size = UDim2.fromScale(1, 1)
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.ScrollBarThickness = 6
			list.AutomaticCanvasSize = Enum.AutomaticSize.Y
			list.CanvasSize = UDim2.new()
			list.Parent = tabPages.coins
			local lay = Instance.new("UIListLayout")
			lay.Padding = UDim.new(0, 10)
			lay.SortOrder = Enum.SortOrder.LayoutOrder
			lay.Parent = list
			pad(list, 6)
			local live = 0
			for i, pr in Config.Products do
				if pr.productId ~= 0 then
					live += 1
					local f = frame(list, { Size = UDim2.new(1, -14, 0, 100), BackgroundColor3 = C.white, LayoutOrder = i })
					corner(f, 16)
					stroke(f, 2, C.ink, 0.15)
					local ic = frame(f, { Size = UDim2.fromOffset(58, 58), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = pr.color })
					corner(ic, 15)
					icon(ic, pr.icon, { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(6, 6) })
					text(f, pr.name, { Size = UDim2.new(1, -270, 0, 26), Position = UDim2.fromOffset(84, 16), Font = DISPLAY, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
					local blurb = pr.desc or (pr.coins and (fmt(pr.coins) .. " coins, straight into your wallet."))
						or (pr.kind == "boost" and (pr.mult .. "x coins for " .. pr.minutes .. " minutes" .. (pr.scope == "server" and ", for everyone here." or ", just for you."))) or ""
					text(f, blurb, { Size = UDim2.new(1, -274, 0, 42), Position = UDim2.fromOffset(84, 42), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
					if pr.badge then
						local bf = frame(f, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(136, 24), Position = UDim2.new(1, -14, 0, 10), BackgroundColor3 = C.mintDark })
						corner(bf, 12)
						text(bf, pr.badge, { Size = UDim2.fromScale(1, 1), Font = DISPLAY, TextSize = 13, TextColor3 = C.white })
					end
					button(f, "R$ " .. pr.robux, { size = UDim2.fromOffset(152, 52), pos = UDim2.new(1, -14, 1, -12), anchor = Vector2.new(1, 1), color = pr.color, textSize = 18, onClick = function()
						if ctx.buyProduct then ctx.buyProduct(pr.id) end
					end })
				end
			end
			if live == 0 then
				text(tabPages.coins, "Nothing here yet.\n\nCash bundles and boosts are created on the Roblox creator dashboard; their ids then go into Config.Products. Until then they stay hidden rather than showing a button that cannot work.", {
					Size = UDim2.new(1, -80, 0, 160), Position = UDim2.fromOffset(40, 40), Font = BODY, TextSize = 16, TextColor3 = C.inkSoft, TextWrapped = true })
			end
		end

		-- HATS (the accessory layer: worn on top of whatever skin you have on)
		local outfitGrid = scroller(tabPages.outfits, UDim2.fromOffset(190, 232))
		local outfitCards = {}
		local function buildOutfitCards(data)
			for _, c in outfitCards do c.frame:Destroy() end
			table.clear(outfitCards)
			local charDef = Config.Character(data.EquippedCharacter)
			for i, o in Config.Outfits do
				local f = frame(outfitGrid, { BackgroundColor3 = C.white, LayoutOrder = i })
				corner(f, 16)
				local st = stroke(f, 2, C.ink, 0.15)
				local bg = frame(f, { Size = UDim2.new(1, -16, 0, 130), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = C.paper2 })
				corner(bg, 12)
				sminskiViewport(bg, charDef, o.id, "idle", { Size = UDim2.fromScale(1, 1) })
				text(f, o.name, { Size = UDim2.new(1, -10, 0, 24), Position = UDim2.fromOffset(5, 142), Font = DISPLAY, TextSize = 19 })
				local b = button(f, "", { size = UDim2.new(1, -24, 0, 50), pos = UDim2.new(0.5, 0, 1, -10), anchor = Vector2.new(0.5, 1), textSize = 20 })
				outfitCards[o.id] = { frame = f, btn = b, stroke = st, def = o }
				b.face.Activated:Connect(function()
					local d = ctx.data
					if d.OwnedOutfits[o.id] then
						if d.EquippedOutfit ~= o.id then ctx.equipOutfit(o.id) end
					else
						ctx.buyOutfit(o.id)
					end
				end)
			end
		end
		local outfitCharBuilt
		local function refreshOutfits()
			local d = ctx.data
			if outfitCharBuilt ~= d.EquippedCharacter then
				outfitCharBuilt = d.EquippedCharacter
				buildOutfitCards(d)
			end
			for id, c in outfitCards do
				local owned = d.OwnedOutfits[id]
				local equipped = d.EquippedOutfit == id
				c.stroke.Color = equipped and C.mintDark or C.ink
				c.stroke.Thickness = equipped and 4 or 2
				if equipped then
					c.btn.setText("WEARING")
					c.btn.setColor(C.mintDark)
				elseif owned then
					c.btn.setText("WEAR")
					c.btn.setColor(C.sky)
				elseif c.def.exclusive then
					c.btn.setText("🎁 " .. string.upper(c.def.exclusive))
					c.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
				elseif c.def.level and (d.Level or 1) < c.def.level then
					c.btn.setText("🔒 LEVEL " .. c.def.level)
					c.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
				else
					c.btn.setText("◉ " .. fmt(c.def.price))
					c.btn.setColor(d.Coins >= c.def.price and C.gold or C.paper2:Lerp(C.inkSoft, 0.3))
				end
			end
		end

		-- UPGRADES tab
		local upList = Instance.new("ScrollingFrame")
		upList.Size = UDim2.fromScale(1, 1)
		upList.BackgroundTransparency = 1
		upList.BorderSizePixel = 0
		upList.ScrollBarThickness = 6
		upList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		upList.CanvasSize = UDim2.new()
		upList.Parent = tabPages.upgrades
		local upLayout = Instance.new("UIListLayout")
		upLayout.Padding = UDim.new(0, 10)
		upLayout.SortOrder = Enum.SortOrder.LayoutOrder
		upLayout.Parent = upList
		pad(upList, 6)
		local upRows = {}
		for i, u in Config.Upgrades do
			local f = frame(upList, { Size = UDim2.new(1, -14, 0, 76), BackgroundColor3 = C.white, LayoutOrder = i })
			corner(f, 16)
			stroke(f, 2, C.ink, 0.15)
			local pdef = Config.Powerups[u.id]
			local ic = frame(f, { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = pdef and pdef.color or C.lav })
			corner(ic, 26)
			text(ic, pdef and pdef.icon or (u.id == "Luck" and "🍀" or "💚"), { Size = UDim2.fromScale(1, 1), Font = DISPLAY, TextSize = 24, TextColor3 = C.white })
			text(f, u.name, { Size = UDim2.new(0.5, 0, 0, 26), Position = UDim2.fromOffset(78, 10), Font = DISPLAY, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			text(f, u.desc, { Size = UDim2.new(0.55, 0, 0, 18), Position = UDim2.fromOffset(78, 40), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			local pips = frame(f, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(#u.costs * 22, 16), Position = UDim2.new(1, -196, 0.5, 0), BackgroundTransparency = 1 })
			local pl = Instance.new("UIListLayout")
			pl.FillDirection = Enum.FillDirection.Horizontal
			pl.Padding = UDim.new(0, 6)
			pl.Parent = pips
			local pipFrames = {}
			for k = 1, #u.costs do
				local p = frame(pips, { Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.paper2 })
				corner(p, 8)
				stroke(p, 1.5, C.ink, 0.3)
				pipFrames[k] = p
			end
			local valueLabel = text(f, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(200, 16), Position = UDim2.new(1, -196, 0, 8), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Right })
			local b = button(f, "", { size = UDim2.fromOffset(160, 54), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 20, onClick = function() ctx.buyUpgrade(u.id) end })
			upRows[u.id] = { pips = pipFrames, btn = b, def = u, value = valueLabel }
		end
		local function refreshUpgrades()
			local d = ctx.data
			for id, r in upRows do
				local lvl = d.Upgrades[id] or 0
				for k, p in r.pips do p.BackgroundColor3 = k <= lvl and C.mint or C.paper2 end
				local cost = r.def.costs[lvl + 1]
				if r.def.unit == "s" then
					r.value.Text = string.format("%.1fs", Config.UpgradeValue(id, lvl)) .. (cost and ("  →  " .. string.format("%.1fs", Config.UpgradeValue(id, lvl + 1))) or "")
				elseif id == "SecondChance" then
					r.value.Text = lvl .. " free revive" .. (lvl == 1 and "" or "s")
				else
					r.value.Text = "level " .. lvl
				end
				if cost then
					r.btn.setText("◉ " .. fmt(cost))
					r.btn.setEnabled(true)
					r.btn.setColor(d.Coins >= cost and C.gold or C.paper2:Lerp(C.inkSoft, 0.3))
				else
					r.btn.setText("MAXED")
					r.btn.setEnabled(false)
				end
			end
		end

		-- CAPSULES tab
		local capPage = tabPages.capsules
		local capHolder, capCard = card(capPage, UDim2.fromOffset(330, 380), UDim2.fromOffset(10, 10), nil, C.white)
		local capVF = Instance.new("ViewportFrame")
		capVF.Size = UDim2.new(1, -20, 0, 250)
		capVF.Position = UDim2.fromOffset(10, 10)
		capVF.BackgroundColor3 = C.paper2
		capVF.Ambient = Color3.fromRGB(210, 210, 200)
		capVF.LightDirection = Vector3.new(-0.5, -1, -0.7)
		corner(capVF, 14)
		capVF.Parent = capCard
		local capWM = Instance.new("WorldModel")
		capWM.Parent = capVF
		local capCam = Instance.new("Camera")
		capCam.FieldOfView = 34
		capCam.CFrame = CFrame.lookAt(Vector3.new(0, 2.4, 9), Vector3.new(0, 1.9, 0))
		capCam.Parent = capVF
		capVF.CurrentCamera = capCam
		local capTop = Models.part(capWM, Vector3.new(3.4, 3.4, 3.4), CFrame.new(0, 2.2, 0), C.coral, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
		local capBottom = Models.part(capWM, Vector3.new(3.42, 1.8, 3.42), CFrame.new(0, 1.3, 0), C.white, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		capBottom.CFrame = CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, math.pi / 2)
		capBottom.Size = Vector3.new(1.8, 3.42, 3.42)
		local capBand = Models.part(capWM, Vector3.new(0.3, 3.5, 3.5), CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.pi / 2), C.ink, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		local capBtn = button(capCard, "OPEN  ◉ " .. Config.CapsuleCost, { size = UDim2.new(1, -30, 0, 64), pos = UDim2.new(0.5, 0, 1, -16), anchor = Vector2.new(0.5, 1), color = C.coral, textSize = 26, onClick = function() ctx.openCapsule() end })
		text(capCard, "mystery toy capsule", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 266), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })

		local oddsHolder, oddsCard = card(capPage, UDim2.new(1, -370, 0, 380), UDim2.fromOffset(360, 10), nil, C.white)
		text(oddsCard, "WHAT'S INSIDE", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 14), Font = DISPLAY, TextSize = 24 })
		local oddsList = frame(oddsCard, { Size = UDim2.new(1, -40, 1, -70), Position = UDim2.fromOffset(20, 56), BackgroundTransparency = 1 })
		local ol = Instance.new("UIListLayout")
		ol.Padding = UDim.new(0, 8)
		ol.Parent = oddsList
		local total = 0
		for _, r in Config.Rarities do total += r.weight end
		for _, r in Config.Rarities do
			local row = frame(oddsList, { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.paper })
			corner(row, 12)
			local chip = frame(row, { Size = UDim2.fromOffset(12, 32), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = r.color })
			corner(chip, 6)
			text(row, r.id, { Size = UDim2.new(0.4, 0, 0, 24), Position = UDim2.fromOffset(32, 4), Font = DISPLAY, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left })
			local names = {}
			for _, c in Config.Characters do
				if c.rarity == r.id then table.insert(names, c.name) end
			end
			text(row, table.concat(names, ", "), { Size = UDim2.new(1, -120, 0, 16), Position = UDim2.fromOffset(32, 29), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			text(row, string.format("%d%%", math.floor(r.weight / total * 100 + 0.5)), { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(80, 30), Position = UDim2.new(1, -12, 0.5, 0), Font = DISPLAY, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right })
		end
		text(oddsCard, "duplicates give coins back", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -30), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft })

		local function refreshShop()
			refreshSkins()
			refreshOutfits()
			refreshUpgrades()
			refreshPasses()
			capBtn.setColor(ctx.data.Coins >= Config.CapsuleCost and C.coral or C.paper2:Lerp(C.inkSoft, 0.3))
		end
		refreshers.shop = function()
			refreshShop()
			local anyVisible = false
			for _, pg in tabPages do anyVisible = anyVisible or pg.Visible end
			if not anyVisible then showTab("skins") end
		end
		function UI.openShopTab(id)
			UI.open("shop")
			showTab(id)
		end

		-- capsule opening overlay
		local capOverlay = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.ink, BackgroundTransparency = 0.35, Visible = false, Active = true, ZIndex = 20 })
		local revealVF = Instance.new("ViewportFrame")
		revealVF.AnchorPoint = Vector2.new(0.5, 0.5)
		revealVF.Size = UDim2.fromOffset(420, 420)
		revealVF.Position = UDim2.fromScale(0.5, 0.42)
		revealVF.BackgroundTransparency = 1
		revealVF.Ambient = Color3.fromRGB(210, 210, 200)
		revealVF.ZIndex = 21
		revealVF.Parent = capOverlay
		local revealName = text(capOverlay, "", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(600, 60), Position = UDim2.new(0.5, 0, 0.42, 190), Font = DISPLAY, TextSize = 54, TextColor3 = C.white, stroke = 4, ZIndex = 22 })
		local revealSub = text(capOverlay, "", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(600, 30), Position = UDim2.new(0.5, 0, 0.42, 250), Font = DISPLAY, TextSize = 26, TextColor3 = C.gold, stroke = 2, ZIndex = 22 })
		local revealBtn = button(capOverlay, "NICE!", { size = UDim2.fromOffset(220, 64), pos = UDim2.new(0.5, 0, 1, -60), anchor = Vector2.new(0.5, 1), textSize = 28, onClick = function()
			capOverlay.Visible = false
			refreshShop()
		end })
		revealBtn.holder.ZIndex = 22
		for _, d in revealBtn.holder:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex = 23 end end

		function UI.playCapsule(result)
			capOverlay.Visible = true
			revealVF:ClearAllChildren()
			revealName.Text = ""
			revealSub.Text = ""
			revealBtn.holder.Visible = false
			local wm = Instance.new("WorldModel")
			wm.Parent = revealVF
			local cam = Instance.new("Camera")
			cam.FieldOfView = 34
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 2.4, 9), Vector3.new(0, 1.9, 0))
			cam.Parent = revealVF
			revealVF.CurrentCamera = cam
			local rarity = Config.Rarity(result.rarity)
			local top = Models.part(wm, Vector3.new(3.4, 3.4, 3.4), CFrame.new(0, 2.2, 0), rarity.color, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball })
			local bottom = Models.part(wm, Vector3.new(1.8, 3.42, 3.42), CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, math.pi / 2), C.white, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
			task.spawn(function()
				-- shake, faster and faster
				for i = 1, 16 do
					local a = math.sin(i * 1.7) * (0.08 + i * 0.012)
					top.CFrame = CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, a)
					bottom.CFrame = CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, a) * CFrame.Angles(0, 0, math.pi / 2)
					Audio.play("Click", 0.8 + i * 0.05, 0.4)
					task.wait(0.09 - i * 0.003)
				end
				-- pop!
				Audio.play("Pop", 0.9, 1)
				UI.flash(rarity.color, 0.7)
				top:Destroy()
				bottom:Destroy()
				local def = Config.Character(result.character)
				local rig = Models.buildSminski(wm, 1, def, false, nil)
				local t0 = os.clock()
				revealName.Text = def.name
				revealName.TextColor3 = rarity.color:Lerp(C.white, 0.3)
				revealSub.Text = result.duplicate and ("duplicate  +◉ " .. result.refund) or (string.upper(rarity.id) .. "  ·  NEW!")
				if rarity.id == "Common" then
					Audio.play("Chime", 1, 0.8)
				else
					Audio.play("BigChime", rarity.id == "Secret" and 0.8 or 1, 1)
				end
				revealBtn.holder.Visible = true
				while capOverlay.Visible and rig.model.Parent do
					local t = os.clock() - t0
					Models.poseSminski(rig, CFrame.Angles(0, t * 1.2, 0), "cheer", t)
					task.wait()
				end
			end)
		end
	end

	---------------------------------------------------------------------------
	-- COLLECTION
	---------------------------------------------------------------------------
	do
		local colBody = modal("collection", "COLLECTION", 900, 590)
		local colCount = text(colBody, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, -2), Font = DISPLAY, TextSize = 20, TextColor3 = C.inkSoft })
		local colArea = frame(colBody, { Size = UDim2.new(1, 0, 1, -32), Position = UDim2.fromOffset(0, 30), BackgroundTransparency = 1 })
		local colGrid = scroller(colArea, UDim2.fromOffset(190, 300))
		local colCards = {}
		for i, c in Config.Characters do
			local rarity = Config.Rarity(c.rarity)
			local f = frame(colGrid, { BackgroundColor3 = C.white, LayoutOrder = i })
			corner(f, 16)
			local st = stroke(f, 2, C.ink, 0.15)
			local bg = frame(f, { Size = UDim2.new(1, -16, 0, 134), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = rarity.color:Lerp(C.white, 0.7) })
			corner(bg, 12)
			local vf = UI.Art.chars[c.id] and icon(bg, "", { Image = UI.Art.chars[c.id], Size = UDim2.new(1, 0, 1, 6), Position = UDim2.fromOffset(0, -3) }) or sminskiViewport(bg, c, nil, c.idle, { Size = UDim2.fromScale(1, 1) })
			local chip = frame(f, { Size = UDim2.fromOffset(72, 20), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = rarity.color })
			corner(chip, 10)
			text(chip, rarity.id, { Size = UDim2.fromScale(1, 1), Font = DISPLAY, TextSize = 13, TextColor3 = C.white })
			local nameL = text(f, c.name, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 146), Font = DISPLAY, TextSize = 21 })
			local pv = Config.Passive(c.id)
			local passL = text(f, pv.name and ("★ " .. pv.name) or "", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 170), Font = DISPLAY, TextSize = 13, TextColor3 = C.mintDark })
			local descL = text(f, pv.desc or "", { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 186), Font = BODY, TextSize = 12, TextColor3 = C.inkSoft, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
			local b = button(f, "", { size = UDim2.new(1, -24, 0, 50), pos = UDim2.new(0.5, 0, 1, -10), anchor = Vector2.new(0.5, 1), textSize = 20, onClick = function()
				if ctx.data.OwnedCharacters[c.id] then
					ctx.equipCharacter(c.id)
				else
					UI.openShopTab("capsules")
				end
			end })
			colCards[c.id] = { vf = vf, name = nameL, btn = b, stroke = st, def = c, pass = passL, desc = descL }
		end
		refreshers.collection = function()
			local d = ctx.data
			local owned = 0
			for id, c in colCards do
				local has = d.OwnedCharacters[id]
				if has then owned += 1 end
				c.vf.ImageColor3 = has and C.white or Color3.fromRGB(40, 45, 40)
				c.vf.ImageTransparency = has and 0 or 0.2
				c.name.Text = has and c.def.name or "???"
				local pv = Config.Passive(id)
				c.pass.Text = has and (pv.name and ("★ " .. pv.name) or "") or "★ ???"
				c.desc.Text = has and (pv.bio and (pv.desc .. "  " .. pv.bio) or pv.desc or "") or "find it in a capsule to learn its trick"
				local eq = d.EquippedCharacter == id
				c.stroke.Color = eq and C.mintDark or C.ink
				c.stroke.Thickness = eq and 4 or 2
				if eq then
					c.btn.setText("EQUIPPED")
					c.btn.setColor(C.mintDark)
				elseif has then
					c.btn.setText("EQUIP")
					c.btn.setColor(C.sky)
				else
					c.btn.setText("CAPSULE")
					c.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
				end
			end
			colCount.Text = owned .. " / " .. #Config.Characters .. " found"
		end
	end

	---------------------------------------------------------------------------
	-- DAILY GIFT: 7-day calendar + streak multiplier
	---------------------------------------------------------------------------
	do
		local body = modal("daily", "DAILY GIFT", 860, 520)
		local streakL = text(body, "", { Size = UDim2.new(1, 0, 0, 30), Font = DISPLAY, TextSize = 26, TextColor3 = C.coral })
		local multL = text(body, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 32), Font = BODY, TextSize = 16, TextColor3 = C.inkSoft })
		local row = frame(body, { Size = UDim2.new(1, 0, 0, 210), Position = UDim2.fromOffset(0, 72), BackgroundTransparency = 1 })
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rl.Padding = UDim.new(0, 10)
		rl.Parent = row
		local tiles = {}
		for i, g in Config.Daily do
			local f = frame(row, { Size = UDim2.fromOffset(106, 200), BackgroundColor3 = C.white, LayoutOrder = i })
			corner(f, 16)
			local st = stroke(f, 2, C.ink, 0.15)
			text(f, "DAY " .. i, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 10), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })
			local badge = frame(f, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0.5, 0, 0, 40), BackgroundColor3 = g.outfit and C.lav or g.capsule and C.coral or C.gold })
			corner(badge, 35)
			icon(badge, g.outfit and "shirt" or g.capsule and "capsule" or "coin", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(7, 7) })
			text(f, g.label, { Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 118), Font = DISPLAY, TextSize = 15, TextWrapped = true })
			local state = text(f, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -32), Font = DISPLAY, TextSize = 15 })
			tiles[i] = { frame = f, stroke = st, state = state }
		end
		local claim = button(body, "CLAIM", { size = UDim2.fromOffset(280, 66), pos = UDim2.new(0.5, 0, 1, -8), anchor = Vector2.new(0.5, 1), color = C.mint, textSize = 30, onClick = function()
			if ctx.claimDaily then ctx.claimDaily() end
		end })
		local note = text(body, "come back tomorrow to keep your streak going · miss a day and it resets", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -100), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft })
		refreshers.daily = function()
			local d = ctx.data or {}
			local L = d.Login or { streak = 1 }
			local streak = math.max(1, L.streak or 1)
			local day = (streak - 1) % #Config.Daily + 1
			streakL.Text = "🔥 " .. streak .. "-DAY STREAK"
			local mult = d.StreakMult or Config.StreakMult(streak)
			multL.Text = string.format("streak bonus: x%.1f coins on runs, rounds and harvests", mult) .. (mult < 1 + Config.Streak.max and "  ·  +10% for each day in a row" or "  ·  maxed!")
			for i, t in tiles do
				local done = i < day or (i == day and not d.DailyReady)
				local today = i == day
				t.stroke.Color = today and C.coral or C.ink
				t.stroke.Transparency = today and 0 or 0.85
				t.stroke.Thickness = today and 4 or 2
				t.frame.BackgroundColor3 = done and C.paper2 or C.white
				t.state.Text = done and "✓ CLAIMED" or today and "TODAY" or ("in " .. (i - day) .. " day" .. (i - day > 1 and "s" or ""))
				t.state.TextColor3 = done and C.mintDark or today and C.coral or C.inkSoft
			end
			claim.setText(d.DailyReady and "CLAIM" or "COME BACK TOMORROW")
			claim.setColor(d.DailyReady and C.mint or C.paper2:Lerp(C.inkSoft, 0.3))
			note.Visible = true
		end
	end

	---------------------------------------------------------------------------
	-- LIVE RUNS: squads running right now + open lobbies at this table
	---------------------------------------------------------------------------
	do
		local body = modal("liveruns", "LIVE RUNS", 760, 540)
		local sub = text(body, "hop into a squad run or an open lobby on this server", { Size = UDim2.new(1, -160, 0, 22), Font = BODY, TextSize = 15, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		local listF = Instance.new("ScrollingFrame")
		listF.Size = UDim2.new(1, 0, 1, -40)
		listF.Position = UDim2.fromOffset(0, 36)
		listF.BackgroundTransparency = 1
		listF.BorderSizePixel = 0
		listF.ScrollBarThickness = 6
		listF.AutomaticCanvasSize = Enum.AutomaticSize.Y
		listF.CanvasSize = UDim2.new()
		listF.Parent = body
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 10)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = listF
		local rows = {}
		local loading = false
		local function clear()
			for _, r in rows do r:Destroy() end
			table.clear(rows)
		end
		local function row(order, title, detail, btnLabel, btnColor, onClick)
			local r = frame(listF, { Size = UDim2.new(1, -8, 0, 76), BackgroundColor3 = C.white, LayoutOrder = order })
			corner(r, 14)
			stroke(r, 2, C.ink, 0.15)
			text(r, title, { Size = UDim2.new(1, -210, 0, 28), Position = UDim2.fromOffset(18, 10), Font = DISPLAY, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			text(r, detail, { Size = UDim2.new(1, -210, 0, 20), Position = UDim2.fromOffset(18, 42), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			if btnLabel then
				button(r, btnLabel, { size = UDim2.fromOffset(170, 52), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), color = btnColor, textSize = 20, onClick = onClick })
			end
			table.insert(rows, r)
			return r
		end
		local function note(order, str)
			local r = text(listF, str, { Size = UDim2.new(1, -8, 0, 30), Font = DISPLAY, TextSize = 17, TextColor3 = C.inkSoft, LayoutOrder = order })
			table.insert(rows, r)
		end
		local function refresh()
			if loading then return end
			loading = true
			clear()
			note(1, "looking around the table...")
			task.spawn(function()
				local d = ctx.mpBrowse and ctx.mpBrowse()
				loading = false
				clear()
				if not d then
					note(1, ctx.mpAvailable and "couldn't reach the server, try again" or "live runs need a live or test server (press Play)")
					return
				end
				local order = 0
				order += 1 note(order, "RUNNING NOW")
				if #d.runs == 0 then
					order += 1 note(order, "nobody is running yet. start one with Quick Play!")
				end
				for _, r in d.runs do
					order += 1
					local who = #r.names > 0 and table.concat(r.names, ", ") or "bots"
					if r.bots > 0 and #r.names > 0 then who ..= "  + " .. r.bots .. " bot" .. (r.bots > 1 and "s" or "") end
					local detail = string.format("%s%s  ·  %d:%02d in  ·  leader at %sm", r.ranked and "RANKED  ·  " or "", r.map or "The Big House", r.secs // 60, r.secs % 60, fmt(r.leadM))
					if r.joinable then
						row(order, who, detail, "JUMP IN", C.mint, function()
							UI.open(nil)
							ctx.mpJoinRun(r.id)
						end)
					else
						row(order, who, detail .. (r.ranked and "" or "  ·  full"), nil)
					end
				end
				order += 1 note(order, "OPEN LOBBIES")
				if #d.lobbies == 0 then
					order += 1 note(order, "no open lobbies. make one from Play Together")
				end
				for _, l in d.lobbies do
					order += 1
					row(order, l.host .. "'s lobby", string.format("code %s  ·  %d / %d players", l.code, l.n, l.max), l.n < l.max and "JOIN" or nil, C.gold, function()
						ctx.mpJoin(l.code)
					end)
				end
				if d.queued > 0 then
					order += 1
					note(order, d.queued .. " waiting in Quick Play right now")
				end
			end)
		end
		button(body, "REFRESH", { size = UDim2.fromOffset(140, 40), pos = UDim2.new(1, 0, 0, -6), anchor = Vector2.new(1, 0), color = C.paper2, textColor = C.ink, textSize = 17, onClick = refresh })
		refreshers.liveruns = refresh
	end

	---------------------------------------------------------------------------
	-- CHALLENGES (daily + weekly goals with coin rewards)
	---------------------------------------------------------------------------
	do
		local chBody = modal("challenges", "GOALS", 820, 580)
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.fromScale(1, 1)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.Parent = chBody
		local ll = Instance.new("UIListLayout")
		ll.Padding = UDim.new(0, 10)
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = list
		local rows = {}
		local function timeLeft(ts)
			local s = math.max(0, (ts or 0) - os.time())
			local h = math.floor(s / 3600)
			if h >= 48 then return math.floor(h / 24) .. "d" end
			return h .. "h " .. math.floor((s % 3600) / 60) .. "m"
		end
		refreshers.challenges = function()
			local d = ctx.data
			local c = d.Challenges
			for _, r in rows do r:Destroy() end
			table.clear(rows)
			if not c then
				local r = text(list, "goals load once you're connected", { Size = UDim2.new(1, 0, 0, 40), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })
				table.insert(rows, r)
				return
			end
			local order = 0
			for _, sec in { { "daily", "DAILY", c.daily, c.dayEnds, C.coral }, { "weekly", "WEEKLY", c.weekly, c.weekEnds, C.lav } } do
				order += 1
				local head = frame(list, { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order })
				text(head, sec[2], { Size = UDim2.new(0.5, 0, 1, 0), Font = DISPLAY, TextSize = 20, TextColor3 = sec[5], TextXAlignment = Enum.TextXAlignment.Left })
				text(head, "resets in " .. timeLeft(sec[4]), { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Right })
				table.insert(rows, head)
				for i, ch in sec[3] or {} do
					order += 1
					local done = ch.progress >= ch.goal
					local r = frame(list, { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = ch.claimed and C.paper2 or C.white, LayoutOrder = order })
					corner(r, 14)
					stroke(r, 2, done and not ch.claimed and C.mintDark or C.ink, 0.15)
					text(r, ch.text, { Size = UDim2.new(1, -220, 0, 26), Position = UDim2.fromOffset(18, 10), Font = DISPLAY, TextSize = 19, TextColor3 = ch.claimed and C.inkSoft or C.ink, TextXAlignment = Enum.TextXAlignment.Left })
					local barBg = frame(r, { Size = UDim2.new(1, -240, 0, 10), Position = UDim2.fromOffset(18, 46), BackgroundColor3 = C.paper2 })
					corner(barBg, 5)
					local bar = frame(barBg, { Size = UDim2.fromScale(math.clamp(ch.progress / ch.goal, 0, 1), 1), BackgroundColor3 = done and C.mintDark or sec[5] })
					corner(bar, 5)
					text(r, fmt(math.min(ch.progress, ch.goal)) .. " / " .. fmt(ch.goal), { Size = UDim2.fromOffset(160, 16), Position = UDim2.new(1, -380, 0, 43), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Right })
					local kind, idx = sec[1], i
					local b = button(r, ch.claimed and "CLAIMED" or ("◉ " .. fmt(ch.reward)), { size = UDim2.fromOffset(170, 50), pos = UDim2.new(1, -16, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 18, color = ch.claimed and C.paper2:Lerp(C.inkSoft, 0.3) or done and C.gold or C.paper2:Lerp(C.inkSoft, 0.15), onClick = function()
						if done and not ch.claimed then ctx.claimChallenge(kind, idx) end
					end })
					table.insert(rows, r)
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- STATS
	---------------------------------------------------------------------------
	do
		local statsBody = modal("stats", "YOUR STATS", 760, 560)
		local statGrid = frame(statsBody, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		local sg = Instance.new("UIGridLayout")
		sg.CellSize = UDim2.new(0.5, -8, 0, 88)
		sg.CellPadding = UDim2.fromOffset(16, 14)
		sg.SortOrder = Enum.SortOrder.LayoutOrder
		sg.Parent = statGrid
		local statTiles = {}
		for i, st in {
			{ "BestScore", "BEST SCORE", C.gold },
			{ "BestDistance", "BEST DISTANCE", C.sky },
			{ "TotalDistance", "TOTAL DISTANCE", C.mint },
			{ "TotalCoins", "COINS COLLECTED", C.gold },
			{ "RunsPlayed", "RUNS", C.lav },
			{ "TotalNearMisses", "NEAR MISSES", C.coral },
			{ "Collection", "SMINSKIS FOUND", C.mint },
			{ "Outfits", "OUTFITS OWNED", C.sky },
		} do
			local f = frame(statGrid, { BackgroundColor3 = C.white, LayoutOrder = i })
			corner(f, 16)
			stroke(f, 2, C.ink, 0.15)
			local chip = frame(f, { Size = UDim2.new(0, 8, 1, -24), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = st[3] })
			corner(chip, 4)
			text(f, st[2], { Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(30, 14), Font = DISPLAY, TextSize = 16, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			statTiles[st[1]] = text(f, "0", { Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(30, 36), Font = DISPLAY, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Left })
		end
		refreshers.stats = function()
			local d = ctx.data
			local m = Config.StudsPerMeter
			statTiles.BestScore.Text = fmt(d.BestScore)
			statTiles.BestDistance.Text = fmt(d.BestDistance / m) .. "m"
			statTiles.TotalDistance.Text = fmt(d.TotalDistance / m) .. "m"
			statTiles.TotalCoins.Text = fmt(d.TotalCoins)
			statTiles.RunsPlayed.Text = fmt(d.RunsPlayed)
			statTiles.TotalNearMisses.Text = fmt(d.TotalNearMisses)
			local owned, outfits = 0, 0
			for _ in d.OwnedCharacters do owned += 1 end
			for id in d.OwnedOutfits do if id ~= "None" then outfits += 1 end end
			statTiles.Collection.Text = owned .. " / " .. #Config.Characters
			statTiles.Outfits.Text = outfits .. " / " .. (#Config.Outfits - 1)
		end
	end

	---------------------------------------------------------------------------
	-- SETTINGS
	---------------------------------------------------------------------------
	do
		local setBody = modal("settings", "SETTINGS", 560, 580)
		local setList = frame(setBody, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		local sl = Instance.new("UIListLayout")
		sl.Padding = UDim.new(0, 12)
		sl.Parent = setList
		local toggles = {}
		for i, s in { { "Music", "Music" }, { "Sfx", "Sound effects" }, { "Shake", "Camera shake" }, { "AutoCam", "Auto-follow camera" } } do
			local row = frame(setList, { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = C.white, LayoutOrder = i })
			corner(row, 16)
			stroke(row, 2, C.ink, 0.15)
			text(row, s[2], { Size = UDim2.new(1, -180, 1, 0), Position = UDim2.fromOffset(22, 0), Font = DISPLAY, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
			local b = button(row, "", { size = UDim2.fromOffset(130, 52), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), textSize = 22, onClick = function()
				ctx.setSetting(s[1], not ctx.data.Settings[s[1]])
			end })
			toggles[s[1]] = b
		end
		do
			local row = frame(setList, { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = C.white, LayoutOrder = 9 })
			corner(row, 16)
			stroke(row, 2, C.ink, 0.15)
			text(row, "Table tour", { Size = UDim2.new(1, -180, 1, 0), Position = UDim2.fromOffset(22, 0), Font = DISPLAY, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
			button(row, "REPLAY", { size = UDim2.fromOffset(130, 52), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.sky, textSize = 22, onClick = function()
				UI.open(nil)
				if ctx.startTour then ctx.startTour() end
			end })
		end
		refreshers.settings = function()
			for k, b in toggles do
				local on = ctx.data.Settings[k]
				b.setText(on and "ON" or "OFF")
				b.setColor(on and C.mint or C.paper2:Lerp(C.inkSoft, 0.3))
			end
		end
	end

	---------------------------------------------------------------------------
	-- REVIVE PROMPT
	---------------------------------------------------------------------------
	local reviveHolder, revive = card(root, UDim2.fromOffset(460, 400), UDim2.fromScale(0.5, 0.56), Vector2.new(0.5, 0.5))
	reviveHolder.Visible = false
	local reviveScale = Instance.new("UIScale")
	reviveScale.Parent = reviveHolder
	text(revive, "ONE MORE RUN?", { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 18), Font = DISPLAY, TextSize = 42 })
	text(revive, "keep going from right here", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 66), Font = BODY, TextSize = 16, TextColor3 = C.inkSoft })
	local timerBg = frame(revive, { Size = UDim2.new(1, -60, 0, 10), Position = UDim2.fromOffset(30, 96), BackgroundColor3 = C.paper2 })
	corner(timerBg, 5)
	local timerFill = frame(timerBg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.coral })
	corner(timerFill, 5)
	local revList = frame(revive, { Size = UDim2.new(1, -60, 1, -140), Position = UDim2.fromOffset(30, 124), BackgroundTransparency = 1 })
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 10)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = revList
	local revFree = button(revList, "FREE REVIVE", { size = UDim2.new(1, 0, 0, 60), color = C.mint, textSize = 26, order = 1, onClick = function() ctx.revive("free") end })
	local revCoins = button(revList, "", { size = UDim2.new(1, 0, 0, 60), color = C.gold, textSize = 26, order = 2, onClick = function() ctx.revive("coins") end })
	local revRobux = button(revList, "REVIVE  (Robux)", { size = UDim2.new(1, 0, 0, 60), color = C.sky, textSize = 24, order = 3, onClick = function() ctx.revive("robux") end })
	local revNo = button(revList, "no thanks", { size = UDim2.new(1, 0, 0, 50), color = C.paper2, textColor = C.ink, textSize = 20, order = 4, releasePitch = 0.9, onClick = function() ctx.declineRevive() end })

	function UI.showRevive(opts)
		reviveHolder.Visible = opts ~= nil
		if not opts then return end
		revFree.holder.Visible = opts.free > 0
		revFree.setText("FREE REVIVE  (" .. opts.free .. " left)")
		revCoins.setText("REVIVE  ◉ " .. fmt(opts.cost))
		revCoins.setEnabled(opts.coins >= opts.cost)
		revRobux.holder.Visible = opts.robux
		local rows = (opts.free > 0 and 1 or 0) + 1 + (opts.robux and 1 or 0)
		reviveHolder.Size = UDim2.fromOffset(460, 150 + rows * 70 + 60)
		reviveScale.Scale = 0.7
		tween(reviveScale, 0.3, { Scale = UI.fit(460, 400) }, Enum.EasingStyle.Back)
	end
	function UI.setReviveTimer(k)
		timerFill.Size = UDim2.fromScale(math.clamp(k, 0, 1), 1)
	end

	---------------------------------------------------------------------------
	-- RESULTS
	---------------------------------------------------------------------------
	local resHolder, res = card(root, UDim2.fromOffset(560, 600), UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0.5))
	resHolder.Visible = false
	local resScale = Instance.new("UIScale")
	resScale.Parent = resHolder
	text(res, "CAUGHT!", { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 16), Font = DISPLAY, TextSize = 50, TextColor3 = C.coral, Rotation = -3 })
	local newBestTag = frame(res, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(180, 30), Position = UDim2.new(0.5, 0, 0, 74), BackgroundColor3 = C.gold, Visible = false })
	corner(newBestTag, 15)
	text(newBestTag, "NEW BEST!", { Size = UDim2.fromScale(1, 1), Font = DISPLAY, TextSize = 20, TextColor3 = C.white })
	local resScore = text(res, "0", { Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 104), Font = DISPLAY, TextSize = 68 })
	text(res, "SCORE", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 170), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })
	local resGrid = frame(res, { Size = UDim2.new(1, -60, 0, 170), Position = UDim2.fromOffset(30, 204), BackgroundTransparency = 1 })
	local rg = Instance.new("UIGridLayout")
	rg.CellSize = UDim2.new(0.5, -6, 0, 76)
	rg.CellPadding = UDim2.fromOffset(12, 12)
	rg.SortOrder = Enum.SortOrder.LayoutOrder
	rg.Parent = resGrid
	local resTiles = {}
	for i, st in { { "distance", "DISTANCE" }, { "coins", "COINS" }, { "combo", "BEST COMBO" }, { "near", "NEAR MISSES" } } do
		local f = frame(resGrid, { BackgroundColor3 = C.paper2, LayoutOrder = i })
		corner(f, 14)
		text(f, st[2], { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 10), Font = DISPLAY, TextSize = 15, TextColor3 = C.inkSoft })
		resTiles[st[1]] = text(f, "0", { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 30), Font = DISPLAY, TextSize = 32 })
	end
	local earnRow = frame(res, { Size = UDim2.new(1, -60, 0, 64), Position = UDim2.fromOffset(30, 386), BackgroundColor3 = C.white })
	corner(earnRow, 14)
	stroke(earnRow, 2, C.ink, 0.15)
	local earnCoins = text(earnRow, "+◉ 0", { Size = UDim2.new(0.5, 0, 1, 0), Font = DISPLAY, TextSize = 28, TextColor3 = C.gold:Lerp(C.ink, 0.2) })
	local earnXP = text(earnRow, "+0 XP", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Font = DISPLAY, TextSize = 28, TextColor3 = C.mintDark })
	local levelUpLabel = text(res, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 454), Font = DISPLAY, TextSize = 20, TextColor3 = C.mintDark })
	local resBtns = frame(res, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -60, 0, 70), Position = UDim2.new(0.5, 0, 1, -22), BackgroundTransparency = 1 })
	local rbl = Instance.new("UIListLayout")
	rbl.FillDirection = Enum.FillDirection.Horizontal
	rbl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rbl.Padding = UDim.new(0, 14)
	rbl.Parent = resBtns
	button(resBtns, "HOME", { size = UDim2.fromOffset(170, 66), color = C.paper2, textColor = C.ink, textSize = 26, order = 1, releasePitch = 0.9, onClick = function() ctx.goHome() end })
	button(resBtns, "RUN AGAIN", { size = UDim2.fromOffset(300, 66), textSize = 30, order = 2, onClick = function() ctx.startRun() end })

	local function countUp(label, to, dur, prefix, suffix)
		prefix, suffix = prefix or "", suffix or ""
		local t0 = os.clock()
		task.spawn(function()
			local lastTick = 0
			while true do
				local k = math.clamp((os.clock() - t0) / dur, 0, 1)
				local e = 1 - (1 - k) ^ 3
				label.Text = prefix .. fmt(to * e) .. suffix
				if os.clock() - lastTick > 0.05 and k < 1 then
					lastTick = os.clock()
					Audio.play("Tick", 1.2 + e, 0.35)
				end
				if k >= 1 then break end
				task.wait()
			end
		end)
	end

	-- stats: { score, distance, coins, bestCombo, nearMisses } ; reward from server (may be nil)
	function UI.showResults(stats, reward)
		resHolder.Visible = stats ~= nil
		if not stats then return end
		resScale.Scale = 0.7
		tween(resScale, 0.35, { Scale = UI.fit(560, 600) }, Enum.EasingStyle.Back)
		newBestTag.Visible = reward and reward.newBest or false
		resScore.Text = "0"
		countUp(resScore, reward and reward.score or stats.score, 1.2)
		task.delay(0.3, function() countUp(resTiles.distance, stats.distance / Config.StudsPerMeter, 0.8, "", "m") end)
		task.delay(0.45, function() countUp(resTiles.coins, stats.coins, 0.8) end)
		resTiles.combo.Text = "x" .. stats.bestCombo
		task.delay(0.6, function() countUp(resTiles.near, stats.nearMisses, 0.6) end)
		earnCoins.Text = "+◉ 0"
		earnXP.Text = "+0 XP"
		levelUpLabel.Text = reward and reward.levelUp and ("LEVEL UP!  now level " .. reward.data.Level) or ""
		if reward and (reward.passBonus or 0) > 0 and not reward.newStars then
			levelUpLabel.Text = "PASS BONUS  +◉ " .. fmt(reward.passBonus) .. (reward.levelUp and "  ·  LEVEL UP!" or "")
		end
		if reward and reward.newStars then
			levelUpLabel.Text = "★ MAP MASTERY " .. string.rep("★", reward.newStars) .. "  +◉ " .. fmt(reward.masteryCoins or 0) .. (reward.levelUp and "  ·  LEVEL UP!" or "")
		end
		if reward then
			task.delay(0.9, function()
				countUp(earnCoins, reward.coinsEarned, 0.8, "+◉ ")
				countUp(earnXP, reward.xpEarned, 0.8, "+", " XP")
				if reward.newBest then
					task.delay(0.8, function()
						Audio.play("BigChime", 1, 1)
						local sc = newBestTag:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", newBestTag)
						sc.Scale = 1.5
						tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
					end)
				end
			end)
		elseif not ctx.data.Saveable then
			levelUpLabel.Text = "offline: rewards not saved"
		end
	end

	---------------------------------------------------------------------------
	-- MULTIPLAYER: menu, lobby, queue bar, squad HUD, down overlay, results
	---------------------------------------------------------------------------
	-- own scope: keeps the main function under Luau's 200-local limit
	local MPUI = {}
	do
		local mpBody = modal("multi", "PLAY TOGETHER", 900, 560)
		-- rank card (left)
		local mpRankHolder, mpRank = card(mpBody, UDim2.fromOffset(300, 440), UDim2.fromOffset(0, 0), nil, C.white)
		text(mpRank, "YOUR RANK", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 18), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })
		local bigChip = frame(mpRank, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(120, 120), Position = UDim2.new(0.5, 0, 0, 52), BackgroundColor3 = C.mint })
		corner(bigChip, 60)
		stroke(bigChip, 3, C.ink, 0.15)
		local bigChipVF = sminskiViewport(bigChip, Config.Characters[1], nil, "cheer", { Size = UDim2.fromScale(1, 1) })
		local mpTierName = text(mpRank, "Glow", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 182), Font = DISPLAY, TextSize = 38 })
		local mpElo = text(mpRank, "1000", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 224), Font = DISPLAY, TextSize = 22, TextColor3 = C.inkSoft })
		local tierBarBg = frame(mpRank, { Size = UDim2.new(1, -60, 0, 12), Position = UDim2.fromOffset(30, 258), BackgroundColor3 = C.paper2 })
		corner(tierBarBg, 6)
		local tierBar = frame(tierBarBg, { Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = C.mint })
		corner(tierBar, 6)
		local tierNext = text(mpRank, "", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 274), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft })
		local mpRecord = text(mpRank, "", { Size = UDim2.new(1, -30, 0, 60), Position = UDim2.fromOffset(15, 310), Font = BODY, TextSize = 15, TextColor3 = C.inkSoft, TextWrapped = true })
		-- tier ladder
		local ladder = frame(mpRank, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -30, 0, 20), Position = UDim2.new(0.5, 0, 1, -16), BackgroundTransparency = 1 })
		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Horizontal
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.Padding = UDim.new(0, 5)
		ll.Parent = ladder
		for _, tr in Config.RankTiers do
			local d = frame(ladder, { Size = UDim2.fromOffset(20, 20), BackgroundColor3 = tr.color })
			corner(d, 10)
			stroke(d, 1.5, C.ink, 0.3)
		end

		-- right side: menu view
		local mpMenu = frame(mpBody, { Size = UDim2.new(1, -320, 1, 0), Position = UDim2.fromOffset(320, 0), BackgroundTransparency = 1 })
		local ml = Instance.new("UIListLayout")
		ml.Padding = UDim.new(0, 12)
		ml.SortOrder = Enum.SortOrder.LayoutOrder
		ml.Parent = mpMenu
		button(mpMenu, "QUICK PLAY", { size = UDim2.new(1, 0, 0, 66), color = C.mint, textSize = 30, order = 1, onClick = function() ctx.mpQueue(false) end })
		text(mpMenu, "up to 3 players · empty spots fill with bots · respawn while your squad survives", { Size = UDim2.new(1, 0, 0, 16), Font = BODY, TextSize = 13, TextColor3 = C.inkSoft, LayoutOrder = 2 })
		button(mpMenu, "RANKED", { size = UDim2.new(1, 0, 0, 66), color = C.lav, textSize = 30, order = 3, onClick = function() ctx.mpQueue(true) end })
		text(mpMenu, "win rating by outscoring your squad · needs 2+ players", { Size = UDim2.new(1, 0, 0, 16), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, LayoutOrder = 4 })
		local lobbyRow = frame(mpMenu, { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, LayoutOrder = 5 })
			button(lobbyRow, "FRIEND LOBBY", { size = UDim2.new(0.5, -6, 0, 58), color = C.gold, textSize = 24, onClick = function() ctx.mpCreate() end })
			button(lobbyRow, "PLAY WITH BOTS", { size = UDim2.new(0.5, -6, 0, 58), pos = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), color = C.coral, textSize = 22, onClick = function() ctx.mpBots() end })
		local joinRow = frame(mpMenu, { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, LayoutOrder = 6 })
		local codeBox = Instance.new("TextBox")
		codeBox.Size = UDim2.new(1, -160, 0, 54)
		codeBox.BackgroundColor3 = C.white
		codeBox.Font = DISPLAY
		codeBox.TextSize = 28
		codeBox.PlaceholderText = "friend code"
		codeBox.PlaceholderColor3 = C.inkSoft
		codeBox.Text = ""
		codeBox.TextColor3 = C.ink
		codeBox.ClearTextOnFocus = false
		corner(codeBox, 14)
		stroke(codeBox, 2, C.ink, 0.15)
		codeBox.Parent = joinRow
		button(joinRow, "JOIN", { size = UDim2.fromOffset(145, 58), pos = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), color = C.sky, textSize = 26, onClick = function() ctx.mpJoin(codeBox.Text) end })
		local mpNote = text(mpMenu, "friends in other servers get pulled into yours", { Size = UDim2.new(1, 0, 0, 16), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, LayoutOrder = 7 })
		button(mpMenu, "LIVE RUNS  ▸", { size = UDim2.new(1, 0, 0, 54), color = C.sky, textSize = 24, order = 8, icon = "play", onClick = function() UI.open("liveruns") end })

		-- right side: lobby view
		local mpLobby = frame(mpBody, { Size = UDim2.new(1, -320, 1, 0), Position = UDim2.fromOffset(320, 0), BackgroundTransparency = 1, Visible = false })
		text(mpLobby, "LOBBY CODE", { Size = UDim2.new(1, 0, 0, 20), Font = DISPLAY, TextSize = 18, TextColor3 = C.inkSoft })
		local lobbyCode = text(mpLobby, "-----", { Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 22), Font = DISPLAY, TextSize = 66, TextColor3 = C.ink })
		text(mpLobby, "share it with up to 2 friends · empty spots become bots", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 92), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft })
		local memberList = frame(mpLobby, { Size = UDim2.new(1, 0, 0, 220), Position = UDim2.fromOffset(0, 122), BackgroundTransparency = 1 })
		local mll = Instance.new("UIListLayout")
		mll.Padding = UDim.new(0, 8)
		mll.Parent = memberList
		local memberRows = {}
		for i = 1, Config.MP.MaxPlayers do
			local row = frame(memberList, { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.white, LayoutOrder = i })
			corner(row, 14)
			stroke(row, 2, C.ink, 0.15)
			local chip = frame(row, { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.paper2 })
			corner(chip, 15)
			local nm = text(row, "waiting for a friend...", { Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(56, 0), Font = DISPLAY, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			local tag = text(row, "", { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(120, 20), Position = UDim2.new(1, -14, 0.5, 0), Font = DISPLAY, TextSize = 16, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Right })
			memberRows[i] = { row = row, chip = chip, name = nm, tag = tag }
		end
		-- the host picks the map (any map they own); friends play it for free
		MPUI.lobbyMap = button(mpLobby, "MAP: THE BIG HOUSE", { size = UDim2.new(1, 0, 0, 50), pos = UDim2.fromOffset(0, 350), color = C.paper2, textColor = C.ink, textSize = 20, onClick = function()
			local lobby = MPUI.getLobby and MPUI.getLobby()
			if not lobby or ctx.myUserId ~= lobby.host then return end
			local owned = {}
			for _, m in Config.Maps do
				if m.free or (ctx.data.OwnedMaps and ctx.data.OwnedMaps[m.id]) then table.insert(owned, m.id) end
			end
			local cur = lobby.map or "house"
			local nextId = owned[1]
			for i, id in owned do
				if id == cur then nextId = owned[i % #owned + 1] end
			end
			if nextId and nextId ~= cur then ctx.mpSetMap(nextId) end
		end })
		local lobbyBtns = frame(mpLobby, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1 })
		local lbl = Instance.new("UIListLayout")
		lbl.FillDirection = Enum.FillDirection.Horizontal
		lbl.Padding = UDim.new(0, 12)
		lbl.Parent = lobbyBtns
		button(lobbyBtns, "LEAVE", { size = UDim2.fromOffset(150, 66), color = C.paper2, textColor = C.ink, textSize = 24, order = 1, releasePitch = 0.9, onClick = function() ctx.mpLeave() end })
		local lobbyStart = button(lobbyBtns, "START", { size = UDim2.new(1, -162, 0, 66), color = C.mint, textSize = 30, order = 2, onClick = function() ctx.mpStart() end })

		-- queue bar (visible on the home page while searching)
		local qHolder, qCard = card(root, UDim2.fromOffset(420, 64), UDim2.new(0.5, 0, 0, 140), Vector2.new(0.5, 0), C.white)
		qHolder.Visible = false
		local qText = text(qCard, "finding players...", { Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(20, 0), Font = DISPLAY, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		button(qCard, "CANCEL", { size = UDim2.fromOffset(120, 46), pos = UDim2.new(1, -10, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.coral, textSize = 20, releasePitch = 0.9, onClick = function() ctx.mpCancel() end })

		qHolder.Parent = nil -- replaced by the FINDING PLAYERS panel below

		-- FINDING PLAYERS: shows anywhere (home page or walking the table)
		-- (own block: keeps this function under Luau's 200-local limit)
		local showFinding, findingShown, hideFinding
		do
		local findDim = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.ink, BackgroundTransparency = 0.45, Visible = false, Active = true, ZIndex = 30 })
		local findHolder, findCard = card(findDim, UDim2.fromOffset(560, 380), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.paper)
		findHolder.ZIndex = 31
		local findTitle = text(findCard, "FINDING PLAYERS", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 22), Font = DISPLAY, TextSize = 36 })
		local findSub = text(findCard, "", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 68), Font = BODY, TextSize = 17, TextColor3 = C.inkSoft })
		local slots = {}
		for i = 1, Config.MP.MaxPlayers do
			local n = Config.MP.MaxPlayers
			local s = frame(findCard, { Size = UDim2.fromOffset(104, 104), Position = UDim2.new(0.5, (i - (n + 1) / 2) * 130 - 52, 0, 110), BackgroundColor3 = i == 1 and C.mint or C.paper2 })
			corner(s, 52)
			stroke(s, 3, C.ink, 0.15)
			local img = icon(s, "", { Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), Visible = i == 1 })
			local q = text(s, "?", { Size = UDim2.fromScale(1, 1), Font = DISPLAY, TextSize = 52, TextColor3 = C.inkSoft, Visible = i ~= 1 })
			local label = text(findCard, i == 1 and "YOU" or "searching", { Size = UDim2.fromOffset(124, 20), Position = UDim2.new(0.5, (i - (n + 1) / 2) * 130 - 62, 0, 220), Font = DISPLAY, TextSize = 15, TextColor3 = C.inkSoft })
			slots[i] = { frame = s, img = img, q = q, label = label }
		end
		local findBarBg = frame(findCard, { Size = UDim2.new(1, -80, 0, 12), Position = UDim2.fromOffset(40, 256), BackgroundColor3 = C.paper2 })
		corner(findBarBg, 6)
		local findBar = frame(findBarBg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.mint })
		corner(findBar, 6)
		local findCount = text(findCard, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 274), Font = DISPLAY, TextSize = 18, TextColor3 = C.ink })
		button(findCard, "CANCEL", { size = UDim2.fromOffset(200, 54), pos = UDim2.new(0.5, 0, 1, -18), anchor = Vector2.new(0.5, 1), color = C.coral, textSize = 22, releasePitch = 0.9, onClick = function() ctx.mpCancel() end })
		local findLoop = false
		local function runFindLoop()
			if findLoop then return end
			findLoop = true
			task.spawn(function()
				local t = 0
				while findDim.Visible do
					t += task.wait(0.1)
					local q = UI._queue
					if not q then break end
					local nowS = ctx.serverNow and ctx.serverNow() or workspace:GetServerTimeNow()
					local waited = math.max(0, nowS - (q.since or nowS))
					local fill = Config.MP.BotFillAfter or 10
					if q.ranked then
						findBar.Size = UDim2.fromScale((waited % 4) / 4, 1)
						findCount.Text = string.format("looking for a fair match  ·  %d:%02d", waited // 60, math.floor(waited % 60))
					else
						local left = math.max(0, fill - waited)
						findBar.Size = UDim2.fromScale(math.clamp(waited / fill, 0, 1), 1)
						findCount.Text = left > 0.05 and ("bots take the empty spots in " .. math.ceil(left) .. "s") or "filling with bots..."
					end
					-- the empty slots pulse while we search
					for i = 2, #slots do
						slots[i].q.TextTransparency = 0.25 + 0.35 * math.sin(t * 5 + i)
					end
				end
				findLoop = false
			end)
		end
		showFinding = function(q)
			UI._queue = q
			findDim.Visible = q ~= nil
			if not q then return end
			findTitle.Text = q.ranked and "RANKED  ·  FINDING PLAYERS" or "FINDING PLAYERS"
			findSub.Text = q.ranked and "matching you with players near your rank" or "quick play  ·  up to " .. Config.MP.MaxPlayers .. " runners"
			local d = ctx.data
			slots[1].img.Image = d and UI.Art.chars[d.EquippedCharacter] or ""
			runFindLoop()
		end
		findingShown = function() return findDim.Visible end
		hideFinding = function() UI._queue = nil findDim.Visible = false end
		end

		local mpState = {}
		MPUI.getLobby = function() return mpState.lobby end
		local function refreshMulti()
			local d = ctx.data
			local elo = d.Elo or Config.MP.StartElo
			local tier, nextTier = Config.RankTier(elo)
			mpTierName.Text = tier.id
			mpTierName.TextColor3 = tier.color:Lerp(C.ink, 0.35)
			mpElo.Text = fmt(elo) .. " rating"
			bigChip.BackgroundColor3 = tier.color
			if nextTier then
				tierBar.Size = UDim2.fromScale(math.clamp((elo - tier.min) / (nextTier.min - tier.min), 0.03, 1), 1)
				tierNext.Text = (nextTier.min - elo) .. " to " .. nextTier.id
			else
				tierBar.Size = UDim2.fromScale(1, 1)
				tierNext.Text = "top tier!"
			end
			tierBar.BackgroundColor3 = tier.color
			mpRecord.Text = string.format("%d ranked wins · %d ranked games\n%d matches played · peak %d", d.RankedWins or 0, d.RankedPlayed or 0, d.MatchesPlayed or 0, d.PeakElo or elo)
			local lobby = mpState.lobby
			mpMenu.Visible = lobby == nil
			mpLobby.Visible = lobby ~= nil
			if lobby then
				lobbyCode.Text = lobby.code
				for i, r in memberRows do
					local m = lobby.members[i]
					if m then
						local mt = Config.RankTier(m.elo or 1000)
						r.chip.BackgroundColor3 = mt.color
						r.name.Text = m.name
						r.name.TextColor3 = C.ink
						r.tag.Text = (m.userId == lobby.host and "HOST · " or "") .. mt.id
					else
						r.chip.BackgroundColor3 = C.paper2
						r.name.Text = "waiting for a friend..."
						r.name.TextColor3 = C.inkSoft
						r.tag.Text = ""
					end
				end
				local amHost = ctx.myUserId == lobby.host
				lobbyStart.setEnabled(amHost)
				lobbyStart.setText(amHost and ("START (" .. #lobby.members .. "/" .. Config.MP.MaxPlayers .. ")") or "host starts")
				local mdef = Config.Map(lobby.map or "house")
				MPUI.lobbyMap.setText(mdef.icon .. "  MAP: " .. string.upper(mdef.name) .. (amHost and "  ▸" or "  ·  host picks"))
				MPUI.lobbyMap.setColor(amHost and mdef.color or C.paper2)
			end
			mpNote.Text = ctx.mpAvailable and "friends in other servers get pulled into yours" or "multiplayer works in a live or test server (press Play)"
		end
		refreshers.multi = refreshMulti

		function UI.setMPStatus(st)
			mpState = st or {}
			showFinding(mpState.queue)
			if currentScreen == "multi" then refreshMulti() end
			-- queued players see the home page with the search bar
			if mpState.queue and currentScreen == "multi" then UI.open(nil) end
		end

		function UI.setQueueTime(secs, ranked)
			if not mpState.queue then return end
			if not findingShown() then showFinding(mpState.queue) end
		end

		-- squad panel during a match
		local squad = frame(hud, { Size = UDim2.fromOffset(230, 140), Position = UDim2.fromOffset(24, 108), BackgroundTransparency = 1, Visible = false })
		local sql = Instance.new("UIListLayout")
		sql.Padding = UDim.new(0, 6)
		sql.Parent = squad
		local squadRows = {}
		for i = 1, Config.MP.MaxPlayers do
			local r = frame(squad, { Size = UDim2.fromOffset(220, 34), BackgroundColor3 = C.paper, LayoutOrder = i, Visible = false })
			corner(r, 17)
			stroke(r, 2, C.ink, 0.1)
			local dot = frame(r, { Size = UDim2.fromOffset(20, 20), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.mint })
			corner(dot, 10)
			local nm = text(r, "", { Size = UDim2.new(1, -90, 1, 0), Position = UDim2.fromOffset(34, 0), Font = DISPLAY, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			local st = text(r, "", { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(70, 20), Position = UDim2.new(1, -10, 0.5, 0), Font = DISPLAY, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right })
			squadRows[i] = { row = r, dot = dot, name = nm, status = st }
		end
		local squadData
		UI._squadRows = squadRows
		function UI.setSquad(list)
			squadData = list
			UI._squadData = list
			squad.Visible = list ~= nil
			puList.Position = list and UDim2.fromOffset(24, 230) or UDim2.fromOffset(24, 120)
		end

		-- "you got caught" overlay while waiting to respawn
		local downHolder, downCard = card(root, UDim2.fromOffset(480, 150), UDim2.new(0.5, 0, 0, 90), Vector2.new(0.5, 0))
		downHolder.Visible = false
		text(downCard, "CAUGHT!", { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 12), Font = DISPLAY, TextSize = 42, TextColor3 = C.coral })
		local downTime = text(downCard, "", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 60), Font = DISPLAY, TextSize = 26 })
		local downSub = text(downCard, "", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 100), Font = BODY, TextSize = 15, TextColor3 = C.inkSoft })
		function UI.showDown(secsLeft, spectating)
			downHolder.Visible = secsLeft ~= nil
			if secsLeft then
				downTime.Text = string.format("back in %.1fs", secsLeft)
				downSub.Text = spectating and ("if your squad survives · watching " .. spectating) or "if your squad survives"
			end
		end

		-- match results
		local mpResHolder, mpRes = card(root, UDim2.fromOffset(620, 560), UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0.5))
		mpResHolder.Visible = false
		local mpResScale = Instance.new("UIScale")
		mpResScale.Parent = mpResHolder
		local mpResTitle = text(mpRes, "SQUAD CAUGHT!", { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 16), Font = DISPLAY, TextSize = 48, TextColor3 = C.coral, Rotation = -2 })
		local mpResSub = text(mpRes, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 72), Font = DISPLAY, TextSize = 20, TextColor3 = C.inkSoft })
		local resList = frame(mpRes, { Size = UDim2.new(1, -60, 0, 230), Position = UDim2.fromOffset(30, 108), BackgroundTransparency = 1 })
		local rll = Instance.new("UIListLayout")
		rll.Padding = UDim.new(0, 8)
		rll.SortOrder = Enum.SortOrder.LayoutOrder
		rll.Parent = resList
		local resRows = {}
		for i = 1, Config.MP.MaxPlayers do
			local r = frame(resList, { Size = UDim2.new(1, 0, 0, 68), BackgroundColor3 = C.paper2, LayoutOrder = i, Visible = false })
			corner(r, 14)
			local st = stroke(r, 2, C.ink, 0.15)
			local place = text(r, "#1", { Size = UDim2.fromOffset(56, 68), Font = DISPLAY, TextSize = 32 })
			local nm = text(r, "", { Size = UDim2.new(0.5, -60, 0, 28), Position = UDim2.fromOffset(60, 8), Font = DISPLAY, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			local sub = text(r, "", { Size = UDim2.new(0.5, -60, 0, 20), Position = UDim2.fromOffset(60, 38), Font = BODY, TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			local sc = text(r, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(180, 30), Position = UDim2.new(1, -16, 0, 8), Font = DISPLAY, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Right })
			local elo = text(r, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(180, 20), Position = UDim2.new(1, -16, 0, 40), Font = DISPLAY, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right })
			resRows[i] = { row = r, stroke = st, place = place, name = nm, sub = sub, score = sc, elo = elo }
		end
		local mpEarn = frame(mpRes, { Size = UDim2.new(1, -60, 0, 60), Position = UDim2.fromOffset(30, 350), BackgroundColor3 = C.white })
		corner(mpEarn, 14)
		stroke(mpEarn, 2, C.ink, 0.15)
		local mpEarnCoins = text(mpEarn, "", { Size = UDim2.new(0.5, 0, 1, 0), Font = DISPLAY, TextSize = 26, TextColor3 = C.gold:Lerp(C.ink, 0.2) })
		local mpEarnXP = text(mpEarn, "", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Font = DISPLAY, TextSize = 26, TextColor3 = C.mintDark })
		local mpResBtns = frame(mpRes, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -60, 0, 70), Position = UDim2.new(0.5, 0, 1, -22), BackgroundTransparency = 1 })
		local mrl = Instance.new("UIListLayout")
		mrl.FillDirection = Enum.FillDirection.Horizontal
		mrl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		mrl.Padding = UDim.new(0, 14)
		mrl.Parent = mpResBtns
		button(mpResBtns, "HOME", { size = UDim2.fromOffset(200, 66), color = C.paper2, textColor = C.ink, textSize = 26, order = 1, releasePitch = 0.9, onClick = function() ctx.goHome() end })
		local againMP = button(mpResBtns, "PLAY AGAIN", { size = UDim2.fromOffset(300, 66), textSize = 30, order = 2 })
		local lastMode

		function UI.showMPResults(d)
			mpResHolder.Visible = d ~= nil
			if not d then return end
			lastMode = d.ranked
			mpResScale.Scale = 0.7
			tween(mpResScale, 0.35, { Scale = UI.fit(620, 560) }, Enum.EasingStyle.Back)
			local won = d.results[1] and d.results[1].userId == d.you and #d.results > 1
			mpResTitle.Text = won and "TOP SMINSKI!" or "SQUAD CAUGHT!"
			mpResTitle.TextColor3 = won and C.gold:Lerp(C.ink, 0.1) or C.coral
			mpResSub.Text = d.ranked and "ranked match" or "unranked match"
			for i, r in resRows do
				local row = d.results[i]
				r.row.Visible = row ~= nil
				if row then
					local me = row.userId == d.you
					r.row.BackgroundColor3 = me and C.mint:Lerp(C.white, 0.55) or C.paper2
					r.stroke.Thickness = me and 3 or 2
					r.place.Text = "#" .. row.place
					r.name.Text = (me and "you" or row.name) .. (row.left and " (left)" or "")
					local tier = Config.RankTier(row.elo or 1000)
					r.sub.Text = fmt((row.distance or 0) / Config.StudsPerMeter) .. "m · " .. tier.id
					r.score.Text = fmt(row.score or 0)
					if row.eloDelta then
						r.elo.Text = (row.eloDelta >= 0 and "+" or "") .. row.eloDelta .. " rating"
						r.elo.TextColor3 = row.eloDelta >= 0 and C.mintDark or C.coral
					else
						r.elo.Text = ""
					end
				end
			end
			local rw = d.reward
			mpEarnCoins.Text = rw and ("+◉ " .. fmt(rw.coinsEarned)) or "+◉ 0"
			mpEarnXP.Text = rw and ("+" .. fmt(rw.xpEarned) .. " XP") or "+0 XP"
		end
		againMP.face.Activated:Connect(function()
			ctx.goHome()
			if ctx.mpQueue then ctx.mpQueue(lastMode == true) end
		end)
		MPUI.qHolder = qHolder
		MPUI.hideFinding = hideFinding
		MPUI.downHolder = downHolder
		MPUI.mpResHolder = mpResHolder
		MPUI.queued = function() return mpState.queue ~= nil end
	end

	---------------------------------------------------------------------------
	-- MAPS
	---------------------------------------------------------------------------
	do
		local mapsBody = modal("maps", "MAPS", 960, 540)
		local row = frame(mapsBody, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.Padding = UDim.new(0, 16)
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rl.Parent = row
		local cards = {}
		for i, m in Config.Maps do
			local f = frame(row, { Size = UDim2.new(1 / #Config.Maps, -12, 1, -6), BackgroundColor3 = C.white, LayoutOrder = i })
			corner(f, 18)
			local st = stroke(f, 2, C.ink, 0.15)
			local art = frame(f, { Size = UDim2.new(1, -20, 0, 170), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = m.color })
			corner(art, 14)
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(m.color:Lerp(C.white, 0.35), m.color:Lerp(C.ink, 0.25))
			g.Rotation = 90
			g.Parent = art
			text(art, m.icon, { Size = UDim2.fromScale(1, 1), TextSize = 90 })
			text(f, m.name, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 188), Font = DISPLAY, TextSize = 28 })
			text(f, m.desc, { Size = UDim2.new(1, -30, 0, 90), Position = UDim2.fromOffset(15, 224), Font = BODY, TextSize = 15, TextColor3 = C.inkSoft, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
			local tag = text(f, "", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -150), Font = DISPLAY, TextSize = 16, TextColor3 = C.inkSoft })
			local starsL = text(f, "", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -174), Font = DISPLAY, TextSize = 17, TextColor3 = C.gold })
			local main = button(f, "", { size = UDim2.new(1, -30, 0, 56), pos = UDim2.new(0.5, 0, 1, -76), anchor = Vector2.new(0.5, 1), textSize = 22, onClick = function()
				local d = ctx.data
				if d.OwnedMaps and d.OwnedMaps[m.id] or m.free then
					ctx.selectMap(m.id)
				else
					ctx.buyMap(m.id)
				end
			end })
			local robux = button(f, "UNLOCK WITH ROBUX", { size = UDim2.new(1, -30, 0, 44), pos = UDim2.new(0.5, 0, 1, -14), anchor = Vector2.new(0.5, 1), color = C.sky, textSize = 17, onClick = function() ctx.buyMapRobux(m.id) end })
			cards[m.id] = { stroke = st, main = main, robux = robux, tag = tag, stars = starsL, def = m }
		end
		refreshers.maps = function()
			local d = ctx.data
			for id, c in cards do
				local owned = c.def.free or (d.OwnedMaps and d.OwnedMaps[id])
				local selected = (d.SelectedMap or "house") == id
				c.stroke.Color = selected and C.mintDark or C.ink
				c.stroke.Thickness = selected and 4 or 2
				do
					local best = d.MapBest and d.MapBest[id] or 0
					local n = Config.MasteryStars(best)
					local nextM = Config.Mastery.starsM[n + 1]
					c.stars.Text = string.rep("★", n) .. string.rep("☆", 3 - n) .. "   " .. fmt(best / Config.StudsPerMeter) .. "m" .. (nextM and ("  ·  next ★ at " .. fmt(nextM) .. "m") or "  ·  mastered!")
				end
				c.robux.holder.Visible = not owned and c.def.gamePassId ~= nil
				if selected then
					c.main.setText("PLAYING")
					c.main.setColor(C.mintDark)
					c.tag.Text = "selected"
				elseif owned then
					c.main.setText("PLAY HERE")
					c.main.setColor(C.mint)
					c.tag.Text = "unlocked"
				else
					c.main.setText("UNLOCK  ◉ " .. fmt(c.def.price or 0))
					c.main.setColor(d.Coins >= (c.def.price or 0) and C.gold or C.paper2:Lerp(C.inkSoft, 0.3))
					c.tag.Text = "solo map · keeps your coins & XP"
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- STATE / REFRESH
	---------------------------------------------------------------------------
	function UI.refresh()
		local d = ctx.data
		if not d then return end
		homeCoins.Text = fmt(d.Coins)
		lvlLabel.Text = tostring(d.Level)
		local lo, hi = Config.XPForLevel(d.Level), Config.XPForLevel(d.Level + 1)
		xpFill.Size = UDim2.fromScale(math.clamp((d.XP - lo) / math.max(1, hi - lo), 0.02, 1), 1)
		xpLabel.Text = fmt(d.XP - lo) .. " / " .. fmt(hi - lo) .. " xp"
		nameLabel.Text = ctx.playerName or "player"
		bestScoreLabel.Text = fmt(d.BestScore)
		bestDistLabel.Text = fmt(d.BestDistance / Config.StudsPerMeter) .. "m"
		runsLabel.Text = fmt(d.RunsPlayed) .. " runs  ·  " .. fmt(d.TotalDistance / Config.StudsPerMeter) .. "m total"
		local tier = Config.RankTier(d.Elo or Config.MP.StartElo)
		rankChip.BackgroundColor3 = tier.color
		rankName.Text = tier.id .. " rank"
		rankElo.Text = fmt(d.Elo or Config.MP.StartElo) .. " rating · " .. (d.RankedWins or 0) .. " ranked wins"
		local selMap = Config.Map(d.SelectedMap or "house")
		mapBtn.setText(selMap.icon .. "  " .. string.upper(selMap.name) .. "  ▸")
		wearChar.Text = Config.Character(d.EquippedCharacter).name
		if UI._giftBtn then
			local streak = d.Login and d.Login.streak or 1
			UI._giftBtn.dot.Visible = d.DailyReady == true
			UI._giftBtn.btn.setText(d.DailyReady and "DAILY GIFT!" or ("STREAK " .. streak .. "  ·  x" .. string.format("%.1f", d.StreakMult or 1)))
		end
		wearOutfit.Text = d.EquippedOutfit ~= "None" and Config.Outfit(d.EquippedOutfit).name or "no outfit"
		saveNote.Text = d.Saveable == false and "progress isn't saving here (turn on Studio API access in Game Settings → Security)" or ""
		if currentScreen and refreshers[currentScreen] then refreshers[currentScreen]() end
	end

	-- which top-level layer is showing: "home" | "run" | "results" | "none"
	function UI.setMode(mode)
		home.Visible = mode == "home"
		if mode == "run" and MPUI.hideFinding then MPUI.hideFinding() end
		if mode ~= "results" then MPUI.mpResHolder.Visible = false end
		if mode ~= "run" then MPUI.downHolder.Visible = false end
		hud.Visible = mode == "run"
		resHolder.Visible = mode == "results" and resHolder.Visible
		if mode ~= "results" then resHolder.Visible = false end
		if mode ~= "revive" then reviveHolder.Visible = false end
		if mode ~= "home" then UI.open(nil) ; modalLayer.Visible = false end
		if mode ~= "run" then
			UI.setDanger(0, 0)
			UI.setSpeedLines(false, 0)
		end
		UI.caught(false)
	end

	-- idle bob on the home title
	---------------------------------------------------------------------------
	-- CROSS-PLATFORM: keep clear of Roblox's top bar, know what the player is
	-- holding (touch / gamepad / keyboard), and give gamepads a selected button
	---------------------------------------------------------------------------
	do
		local GuiService = game:GetService("GuiService")
		local UIS = game:GetService("UserInputService")
		local function applyInsets()
			local inset = GuiService:GetGuiInset().Y
			-- design pixels, so derived from the viewport for the same reason
			local _, _, sc = canvas()
			local padPx = math.max(0, inset - 20) / sc
			for _, fr in { hud, home } do
				local p = fr:FindFirstChild("TopInset") or Instance.new("UIPadding")
				p.Name = "TopInset"
				p.PaddingTop = UDim.new(0, padPx)
				p.Parent = fr
			end
		end
		applyInsets()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyInsets)

		local kind = UIS.GamepadEnabled and not UIS.KeyboardEnabled and "gamepad" or UIS.TouchEnabled and not UIS.KeyboardEnabled and "touch" or "keyboard"
		local listeners = {}
		function UI.inputKind() return kind end
		function UI.onInputKind(fn)
			table.insert(listeners, fn)
			fn(kind)
		end
		local function visible(g)
			local a = g
			while a and a ~= gui do
				if a:IsA("GuiObject") and not a.Visible then return false end
				a = a.Parent
			end
			return true
		end
		-- pick the most useful button on whatever is showing
		function UI.autoSelect()
			if kind ~= "gamepad" then
				GuiService.SelectedObject = nil
				return
			end
			local cur = GuiService.SelectedObject
			if cur and cur:IsDescendantOf(gui) and visible(cur) and (not modalLayer.Visible or cur:IsDescendantOf(modalLayer)) then return end
			local scope = modalLayer.Visible and modalLayer or root
			local first, preferred
			for _, d in scope:GetDescendants() do
				if d:IsA("GuiButton") and d.Selectable and visible(d) then
					first = first or d
					local t = d:IsA("TextButton") and d.Text or ""
					if not preferred and (t:find("RUN SOLO") or t:find("PLAY AGAIN") or t:find("REVIVE") or t:find("EQUIP") or t:find("CLAIM")) then preferred = d end
				end
			end
			GuiService.SelectedObject = preferred or first
		end
		UIS.LastInputTypeChanged:Connect(function(t)
			local k = kind
			if t == Enum.UserInputType.Touch then
				k = "touch"
			elseif t.Name:find("Gamepad") then
				k = "gamepad"
			elseif t == Enum.UserInputType.Keyboard or t.Name:find("Mouse") then
				k = "keyboard"
			end
			if k ~= kind then
				kind = k
				for _, fn in listeners do task.spawn(fn, kind) end
				UI.autoSelect()
			end
		end)
		local openBase, modeBase = UI.open, UI.setMode
		function UI.open(name)
			openBase(name)
			task.defer(UI.autoSelect)
		end
		function UI.setMode(mode)
			modeBase(mode)
			task.defer(UI.autoSelect)
		end
	end

	task.spawn(function()
		local t = 0
		while gui.Parent ~= nil or t == 0 do
			t += task.wait()
			if home.Visible then
				title.Rotation = math.sin(t * 1.3) * 1.2
			end
		end
	end)

	return UI
end
