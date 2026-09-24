--This Movement System made by Chornovose/@KMB910285

-- Jump, Fall and Land Animation System
-- Player cannot move for 0.5 seconds after landing

local Players = game:GetService("Players")
local RunService = game:getService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Settings
local LAND_FREEZE_DURATION = 0.5  -- Seconds of no movement after landing
local WALK_SPEED = 15            -- Normal walk speed

-- Animation IDs (you can add your own animations)
local JUMP_ANIM_ID = "rbxassetid://94441971716818"      -- Jump animation
local FALL_ANIM_ID = "rbxassetid://111199145041098"      -- Fall animation  
local LAND_ANIM_ID = "rbxassetid://89874231257627"     -- Land animation

-- Variables
local humanoid = nil
local animator = nil
local rootPart = nil
local isJumping = false
local isFalling = false
local isLanding = false
local isFrozen = false

-- Global access (other scripts can use)
_G.IsLanding = false
_G.IsFrozen = false

-- Animation tracks
local jumpTrack = nil
local fallTrack = nil
local landTrack = nil

-- Animation objects
local animJump = Instance.new("Animation")
animJump.AnimationId = JUMP_ANIM_ID

local animFall = Instance.new("Animation")
animFall.AnimationId = FALL_ANIM_ID

local animLand = Instance.new("Animation")
animLand.AnimationId = LAND_ANIM_ID

-- Update character variables
local function refreshCharacter()
	local character = LocalPlayer.Character
	if not character then return false end
	
	humanoid = character:FindFirstChild("Humanoid")
	rootPart = character:FindFirstChild("HumanoidRootPart")
	
	if humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	end
	
	return humanoid ~= nil and animator ~= nil and rootPart ~= nil
end

-- Load animations
local function loadAnimations()
	if not animator then return end
	
	jumpTrack = animator:LoadAnimation(animJump)
	jumpTrack.Priority = Enum.AnimationPriority.Action
	
	fallTrack = animator:LoadAnimation(animFall)
	fallTrack.Priority = Enum.AnimationPriority.Action
	
	landTrack = animator:LoadAnimation(animLand)
	landTrack.Priority = Enum.AnimationPriority.Action
end

-- Stop all animations
local function stopAllAnimations()
	if jumpTrack and jumpTrack.IsPlaying then
		jumpTrack:Stop(0.1)
	end
	if fallTrack and fallTrack.IsPlaying then
		fallTrack:Stop(0.1)
	end
	if landTrack and landTrack.IsPlaying then
		landTrack:Stop(0.1)
	end
end

-- Play jump animation
local function playJumpAnimation()
	if not jumpTrack then return end
	stopAllAnimations()
	jumpTrack:Play(0.1)
end

-- Play fall animation
local function playFallAnimation()
	if not fallTrack then return end
	if fallTrack.IsPlaying then return end
	stopAllAnimations()
	fallTrack:Play(0.1)
end

-- Play land animation and freeze movement
local function playLandAnimation()
	if not landTrack then return end
	stopAllAnimations()
	landTrack:Play(0.1)
	
	-- Freeze movement
	if humanoid and not isFrozen then
		isFrozen = true
		_G.IsFrozen = true
		_G.IsLanding = true
		humanoid.WalkSpeed = 0
		
		-- Can move again after 0.5 seconds
		task.delay(LAND_FREEZE_DURATION, function()
			if humanoid then
				humanoid.WalkSpeed = WALK_SPEED
			end
			isFrozen = false
			_G.IsFrozen = false
			_G.IsLanding = false
		end)
	end
end

-- Monitor state changes
local function onStateChanged(oldState, newState)
	-- Update character variables if not ready
	if not humanoid or not animator then
		if not refreshCharacter() then return end
	end
	
	-- Jump started
	if newState == Enum.HumanoidStateType.Jumping then
		isJumping = true
		isFalling = false
		isLanding = false
		playJumpAnimation()
		
	-- Fall started
	elseif newState == Enum.HumanoidStateType.Freefall then
		if isJumping then
			isJumping = false
		end
		isFalling = true
		isLanding = false
		playFallAnimation()
		
	-- Landed
	elseif newState == Enum.HumanoidStateType.Landed then
		if isFalling or isJumping then
			isJumping = false
			isFalling = false
			isLanding = true
			playLandAnimation()
		end
		
	-- Running or walking started (exit from landing)
	elseif newState == Enum.HumanoidStateType.Running or newState == Enum.HumanoidStateType.RunningNoPhysics then
		if isLanding then
			isLanding = false
		end
		isJumping = false
		isFalling = false
	end
end

-- When character spawns
local function onCharacterAdded(character)
	-- Reset variables
	isJumping = false
	isFalling = false
	isLanding = false
	isFrozen = false
	jumpTrack = nil
	fallTrack = nil
	landTrack = nil
	
	-- Get character variables
	if refreshCharacter() then
		loadAnimations()
		
		-- Monitor state changes
		humanoid.StateChanged:Connect(onStateChanged)
	end
end

-- When character is added
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- Initial load
if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end