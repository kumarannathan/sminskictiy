-- Audio: music that intensifies with speed/danger, heartbeat + footsteps
-- for the chase, tactile SFX with small voice pools and pitch variation.

return function(Config)
	local SoundService = game:GetService("SoundService")
	local TweenService = game:GetService("TweenService")

	local Audio = {}
	local S = Config.Sounds

	local folder = Instance.new("Folder")
	folder.Name = "SminskiAudio"
	folder.Parent = SoundService
	Audio.folder = folder

	local function group(name, vol)
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = vol
		g.Parent = folder
		return g
	end
	local musicGroup = group("Music", 1)
	local sfxGroup = group("Sfx", 1)
	local chaseGroup = group("Chase", 1)

	-- music "tone": muffled + warm when calm, opens up when intense
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = 2
	eq.MidGain = -2
	eq.HighGain = -14
	eq.Parent = musicGroup

	local musicOn, sfxOn = true, true

	---------------------------------------------------------------------------
	-- MUSIC
	---------------------------------------------------------------------------
	local layers = {}
	for i, l in S.MusicLayers do
		local snd = Instance.new("Sound")
		snd.Name = "MusicLayer" .. i
		snd.SoundId = l.id
		snd.Looped = true
		snd.Volume = 0
		snd.SoundGroup = musicGroup
		snd.Parent = folder
		table.insert(layers, { sound = snd, from = l.from, volume = l.volume })
	end

	local heartbeat = Instance.new("Sound")
	heartbeat.SoundId = S.Heartbeat
	heartbeat.Looped = true
	heartbeat.Volume = 0
	heartbeat.SoundGroup = chaseGroup
	heartbeat.Parent = folder

	local musicLevel = 0 -- 0..1 master fade
	local musicTarget = 0
	local intensity = 0
	local slow = 0

	function Audio.musicStart(fade)
		if not musicOn then return end
		for _, l in layers do
			if not l.sound.IsPlaying then
				l.sound.TimePosition = 0
				l.sound:Play()
			end
		end
		if not heartbeat.IsPlaying then heartbeat:Play() end
		musicTarget = 1
		if fade == false then musicLevel = 1 end
	end

	-- abrupt=true cuts instantly (getting caught)
	function Audio.musicStop(abrupt)
		musicTarget = 0
		if abrupt then
			musicLevel = 0
			for _, l in layers do l.sound.Volume = 0 end
			heartbeat.Volume = 0
		end
	end

	-- lobby: a soft lofi loop instead of the chase music
	local ambient
	if S.Lobby then
		ambient = Instance.new("Sound")
		ambient.Name = "Lobby"
		ambient.SoundId = S.Lobby
		ambient.Looped = true
		ambient.Volume = 0
		ambient.SoundGroup = musicGroup
		ambient.Parent = folder
	end
	-- A GENERATION TOKEN, because turning this on yields.
	--
	-- ambient(true) spawns a coroutine that waits for the sound to LOAD. Boot
	-- calls ambient(true) and then ambient(false) a frame later on the way
	-- into the city -- and the first coroutine was still parked on Loaded.
	-- When the file finally arrived it happily Played and faded the lobby
	-- loop back up, over the city's own ambience and the menu music. Two
	-- tracks at once, and no obvious culprit because the call that started it
	-- had returned long ago.
	local ambientGen = 0
	function Audio.ambient(on)
		if not ambient then return end
		ambientGen += 1
		local gen = ambientGen
		if on and musicOn then
			task.spawn(function()
				if not ambient.IsLoaded then ambient.Loaded:Wait() end
				if gen ~= ambientGen then return end   -- switched off while we waited
				if not ambient.IsPlaying then ambient:Play() end
				TweenService:Create(ambient, TweenInfo.new(1.5), { Volume = 0.35 }):Play()
			end)
		else
			TweenService:Create(ambient, TweenInfo.new(0.8), { Volume = 0 }):Play()
			task.delay(0.9, function() if ambient.Volume < 0.01 then ambient:Stop() end end)
		end
	end

	function Audio.musicSoft()
		-- menus: quiet, very muffled
		Audio.musicStart()
		musicTarget = 0.55
		intensity = 0
	end

	-- call every frame. intensity 0..1 (speed), danger 0..1 (kid distance)
	function Audio.update(dt, targetIntensity, danger, slowOn)
		intensity += (targetIntensity - intensity) * math.min(1, dt * 0.8)
		slow += ((slowOn and 1 or 0) - slow) * math.min(1, dt * 4)
		musicLevel += (musicTarget - musicLevel) * math.min(1, dt * (musicTarget > musicLevel and 1.2 or 3))
		local k = math.clamp(intensity + danger * 0.35, 0, 1)
		eq.HighGain = -14 + 14 * k - slow * 10
		eq.MidGain = -2 + 2 * k
		eq.LowGain = 2 + 2 * k
		for i, l in layers do
			local on = (k >= l.from) and 1 or 0
			local target = (musicOn and l.volume or 0) * musicLevel * on
			l.sound.Volume += (target - l.sound.Volume) * math.min(1, dt * 2)
			l.sound.PlaybackSpeed = (1 + 0.12 * k) * (1 - slow * 0.15)
			-- keep stems in sync with the first layer
			if i > 1 and layers[1].sound.IsPlaying and math.abs(l.sound.TimePosition - layers[1].sound.TimePosition) > 0.08 then
				l.sound.TimePosition = layers[1].sound.TimePosition
			end
		end
		local hb = musicOn and math.clamp((danger - 0.25) / 0.75, 0, 1) * 0.7 * musicLevel or 0
		heartbeat.Volume += (hb - heartbeat.Volume) * math.min(1, dt * 3)
		heartbeat.PlaybackSpeed = 1 + danger * 0.45
	end

	---------------------------------------------------------------------------
	-- SFX (small voice pools so rapid sounds don't cut each other off)
	---------------------------------------------------------------------------
	local pools = {}
	local function pool(name, id, vol, voices)
		local p = { i = 1, voices = {}, vol = vol }
		for v = 1, voices or 2 do
			local snd = Instance.new("Sound")
			snd.Name = name .. v
			snd.SoundId = id
			snd.Volume = vol
			snd.SoundGroup = name == "Stomp" and chaseGroup or sfxGroup
			snd.Parent = folder
			table.insert(p.voices, snd)
		end
		pools[name] = p
	end
	pool("Tick", S.Tick, 0.35, 5)
	pool("Click", S.Click, 0.4, 3)
	pool("Whoosh", S.Whoosh, 0.18, 3)
	pool("Pop", S.Pop, 0.35, 3)
	pool("Chime", S.Chime, 0.35, 2)
	pool("BigChime", S.BigChime, 0.4, 1)
	pool("Wobble", S.Wobble, 0.5, 1)
	pool("Jump", S.Jump, 0.3, 2)
	pool("Land", S.Land, 0.22, 2)
	pool("Bump", S.Bump, 0.5, 2)
	pool("Stomp", S.Stomp, 0.0, 3)
	if S.Bark then pool("Bark", S.Bark, 0.6, 2) end

	function Audio.play(name, pitch, volMul)
		if not sfxOn and name ~= "Stomp" then return end
		local p = pools[name]
		if not p then return end
		local snd = p.voices[p.i]
		p.i = p.i % #p.voices + 1
		snd.PlaybackSpeed = pitch or 1
		snd.Volume = p.vol * (volMul or 1)
		snd.TimePosition = 0
		snd:Play()
	end

	-- coin ticks climb a pentatonic scale while you keep collecting
	local SCALE = { 1, 1.122, 1.26, 1.498, 1.682, 2, 2.245, 2.52 }
	local coinStep, lastCoin = 0, 0
	function Audio.coin(now, gold)
		if now - lastCoin > 0.7 then coinStep = 0 end
		lastCoin = now
		coinStep = coinStep % #SCALE + 1
		Audio.play("Tick", 1.5 * SCALE[coinStep], gold and 1.4 or 1)
		if gold then Audio.play("Chime", 1.4, 0.6) end
	end

	-- the kid's footsteps: louder + deeper as he gets closer
	function Audio.stomp(danger)
		if danger <= 0.05 then return end
		Audio.play("Stomp", 0.55 + (1 - danger) * 0.1, math.clamp(danger, 0, 1) * 3)
	end

	-- brief duck of music for critical sounds (bumps, caught)
	function Audio.duck(amount, time)
		musicGroup.Volume = 1 - amount
		TweenService:Create(musicGroup, TweenInfo.new(time or 0.6), { Volume = 1 }):Play()
	end

	function Audio.setEnabled(music, sfx)
		musicOn = music
		sfxOn = sfx
		if not musicOn then
			for _, l in layers do l.sound.Volume = 0 end
			heartbeat.Volume = 0
			if ambient then ambient.Volume = 0 end
		end
	end

	function Audio.destroy()
		folder:Destroy()
	end

	return Audio
end
