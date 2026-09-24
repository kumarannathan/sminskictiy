--This Movement System made by Chornovose/@KMB910285

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

-- EMOTE SETTINGS
local EMOTE_ANIMATION_ID = "rbxassetid://85137567491887" -- Emote animation ID (change this)
local EMOTE_KEY = Enum.KeyCode.G -- Emote key
local MOVEMENT_DISABLE_TIME = 6.5 -- Movement disable duration (seconds)

-- State variables
local emoteTrack = nil
local isPlayingEmote = false
local isMovementDisabled = false
local originalWalkSpeed = 16

-- Load emote animation
local function loadEmoteAnimation()
	local anim = Instance.new("Animation")
	anim.AnimationId = EMOTE_ANIMATION_ID
	return animator:LoadAnimation(anim)
end

-- Disable movement
local function disableMovement()
	isMovementDisabled = true
	originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	
	task.wait(MOVEMENT_DISABLE_TIME)
	
	isMovementDisabled = false
	humanoid.WalkSpeed = originalWalkSpeed
end

-- Play emote
local function playEmote()
	if isPlayingEmote then
		-- Stop if already playing
		if emoteTrack then
			emoteTrack:Stop()
			isPlayingEmote = false
			isMovementDisabled = false
			humanoid.WalkSpeed = originalWalkSpeed
		end
		return
	end
	
	-- Don't play emote while rolling
	if _G.IsRolling then
		return
	end
	
	-- Don't play emote if player is moving
	if humanoid.MoveDirection.Magnitude > 0.1 then
		return
	end
	
	-- Play the emote
	if not emoteTrack then
		emoteTrack = loadEmoteAnimation()
	end
	
	emoteTrack:Play()
	isPlayingEmote = true
	
	-- Disable movement for 1 second
	task.spawn(disableMovement)
	
	-- When animation ends
	task.spawn(function()
		emoteTrack.Stopped:Wait()
		isPlayingEmote = false
	end)
end

-- Key input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == EMOTE_KEY then
		playEmote()
	end
end)

-- When character respawns
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")
	
	-- Reset state
	isPlayingEmote = false
	emoteTrack = nil
end)