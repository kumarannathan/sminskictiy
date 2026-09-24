--This Movement System made by Chornovose/@KMB910285

-- Crouch System
-- Press C to crouch, press again to stand up

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local SmoothShiftLock = nil

-- Find SmoothShiftLock module
local function getShiftLockModule()
	local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if playerScripts then
		local customShiftLock = playerScripts:FindFirstChild("CustomShiftLock")
		if customShiftLock then
			local smoothShiftLock = customShiftLock:FindFirstChild("SmoothShiftLock")
			if smoothShiftLock and smoothShiftLock:IsA("ModuleScript") then
				return require(smoothShiftLock)
			end
		end
	end
	return nil
end

-- Settings
local CROUCH_SPEED = 10       -- Walk speed while crouching
local WALK_SPEED = 15        -- Normal walk speed

-- Animation IDs
local CROUCH_IDLE_ID = "rbxassetid://111830268730428"
local CROUCH_WALK_ID = "rbxassetid://92337719766551"

-- Variables
local isCrouching = false

-- Global access (other scripts can use)
_G.IsCrouching = false
local humanoid = nil
local animator = nil
local crouchIdleTrack = nil
local crouchWalkTrack = nil
local currentTrack = nil
local isMoving = false
local animateScript = nil

-- Animation objects
local animCrouchIdle = Instance.new("Animation")
animCrouchIdle.AnimationId = CROUCH_IDLE_ID

local animCrouchWalk = Instance.new("Animation")
animCrouchWalk.AnimationId = CROUCH_WALK_ID

-- Update character variables
local function refreshCharacter()
	local character = LocalPlayer.Character
	if not character then return false end
	
	humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	end
	
	return humanoid ~= nil and animator ~= nil
end

-- Load animations
local function loadAnimations()
	if not animator then return end
	
	crouchIdleTrack = animator:LoadAnimation(animCrouchIdle)
	crouchIdleTrack.Priority = Enum.AnimationPriority.Action
	
	crouchWalkTrack = animator:LoadAnimation(animCrouchWalk)
	crouchWalkTrack.Priority = Enum.AnimationPriority.Action
end

-- Update animation
local function updateAnimation()
	if not isCrouching then return end
	
	local targetTrack = isMoving and crouchWalkTrack or crouchIdleTrack
	if not targetTrack then return end
	
	-- Don't replay if same animation is already playing
	if currentTrack == targetTrack and targetTrack.IsPlaying then
		return
	end
	
	-- Stop previous animation
	if currentTrack and currentTrack.IsPlaying then
		currentTrack:Stop(0.1)
	end
	
	currentTrack = targetTrack
	currentTrack:Play(0.1)
end

-- Stop Animate script
local function stopAnimateScript()
	local character = LocalPlayer.Character
	if character then
		animateScript = character:FindFirstChild("Animate")
		if animateScript then
			animateScript.Disabled = true
		end
	end
end

-- Start Animate script
local function startAnimateScript()
	if animateScript then
		animateScript.Disabled = false
	end
end

-- Start crouching
local function startCrouch()
	if isCrouching then return end
	if _G.IsRolling then return end  -- Cannot crouch while rolling
	
	if not refreshCharacter() then return end
	
	-- Load animations (first time)
	if not crouchIdleTrack then
		loadAnimations()
	end
	
	isCrouching = true
	_G.IsCrouching = true
	humanoid.WalkSpeed = CROUCH_SPEED
	stopAnimateScript()
	
	updateAnimation()
end

-- Stop crouching
local function stopCrouch()
	if not isCrouching then return end
	
	isCrouching = false
	_G.IsCrouching = false
	
	-- Stop animation
	if currentTrack and currentTrack.IsPlaying then
		currentTrack:Stop(0.1)
	end
	currentTrack = nil
	
	-- Restore speed to normal
	if humanoid then
		humanoid.WalkSpeed = WALK_SPEED
	end
	
	startAnimateScript()
end

-- Check movement state
local function checkMovement()
	if not humanoid then return end
	
	local moveDirection = humanoid.MoveDirection
	local wasMoving = isMoving
	isMoving = moveDirection.Magnitude > 0.1
	
	-- Update animation if movement state changed
	if isCrouching and isMoving ~= wasMoving then
		updateAnimation()
	end
end

-- Key input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.C then
		if isCrouching then
			stopCrouch()
		else
			startCrouch()
		end
	end
end)

-- Movement check every frame
RunService.Heartbeat:Connect(function()
	if isCrouching and not _G.IsRolling then
		checkMovement()
		
		-- Get ShiftLock module if not yet acquired
		if not SmoothShiftLock then
			SmoothShiftLock = getShiftLockModule()
		end
		
		-- Only preserve WalkSpeed if ShiftLock is OFF
		-- When ShiftLock is ON, ShiftLockSpeedReducer handles speed reductions
		local isShiftLockOn = SmoothShiftLock and SmoothShiftLock.Enabled
		if not isShiftLockOn then
			if humanoid and humanoid.WalkSpeed ~= CROUCH_SPEED then
				humanoid.WalkSpeed = CROUCH_SPEED
			end
		end
	end
end)

-- Reset when character spawns
LocalPlayer.CharacterAdded:Connect(function()
	isCrouching = false
	crouchIdleTrack = nil
	crouchWalkTrack = nil
	currentTrack = nil
	isMoving = false
	animateScript = nil
end)