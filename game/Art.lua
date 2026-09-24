-- Art (ReplicatedStorage.SminskiShared.Art)
-- Uploaded image ids for the Blender-rendered UI art (see art/blender/*.py).
-- Re-render + re-upload, then update these ids.

local Art = {}

Art.logo = "rbxassetid://86239266364583"
Art.hero = "rbxassetid://103450079715685"

-- tintable surfaces: base (tint with ImageColor3) + untinted gloss overlay
Art.ui = {
	pill = { base = "rbxassetid://99657844019092", gloss = "rbxassetid://97391711534640", size = Vector2.new(512, 160), corner = 80 },
	key = { base = "rbxassetid://138123926039588", gloss = "rbxassetid://108723651643110", size = Vector2.new(512, 160), corner = 36 },
	card = { base = "rbxassetid://75930661398282", gloss = "rbxassetid://138290243393708", size = Vector2.new(512, 512), corner = 64 },
	disc = { base = "rbxassetid://83510130191298", gloss = "rbxassetid://96620764832524", size = Vector2.new(256, 256), corner = 128 },
}

Art.icons = {
	bag = "rbxassetid://93443946610849",
	bolt = "rbxassetid://89556041455362",
	capsule = "rbxassetid://72391977362202",
	chart = "rbxassetid://133655204103548",
	clock = "rbxassetid://77207325992017",
	coin = "rbxassetid://80552627031159",
	crown = "rbxassetid://101195423074105",
	dog = "rbxassetid://125517002311790",
	friends = "rbxassetid://133005970089585",
	gear = "rbxassetid://133966172818876",
	heart = "rbxassetid://95676902868697",
	hourglass = "rbxassetid://75034171418656",
	house = "rbxassetid://98925649332484",
	lock = "rbxassetid://78634026624489",
	magnet = "rbxassetid://84794166139637",
	paw = "rbxassetid://74333375857134",
	pin = "rbxassetid://130917909666859",
	play = "rbxassetid://76050131788638",
	shield = "rbxassetid://100049017134984",
	shirt = "rbxassetid://109761039204335",
	star = "rbxassetid://99322292877366",
	trophy = "rbxassetid://79637510885710",
	x2 = "rbxassetid://108623554552581",
}

-- which icon each powerup uses
Art.powerup = { Magnet = "magnet", Doubler = "x2", Shield = "shield", SlowTime = "hourglass", Boost = "bolt" }

-- glossy portraits of every Sminski (no outfit)
Art.chars = {
	Glow = "rbxassetid://91758739475236",
	Blush = "rbxassetid://103892276563669",
	Sky = "rbxassetid://127581141845691",
	Lemon = "rbxassetid://132416684527478",
	Lavender = "rbxassetid://129278615441101",
	Mint = "rbxassetid://139404449258053",
	Peach = "rbxassetid://116432688852154",
	Ghost = "rbxassetid://85677411871220",
	Night = "rbxassetid://140380333229638",
	Galaxy = "rbxassetid://115878721898023",
	Secret = "rbxassetid://86346361485442",
}

return Art
