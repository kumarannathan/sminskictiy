--This Movement System made by Chornovose/@KMB910285

-- ShiftLock Directional Animations
-- Plays different animations based on direction when ShiftLock is on

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local SmoothShiftLock = nil

-- Animation IDs
local ANIM_BACKWARD = "rbxassetid://90698324861617"  -- Backward
local ANIM_RIGHT = "rbxassetid://91677029738372"     -- Right
local ANIM_LEFT = "rbxassetid://138109256991511"     -- Left

-- Variables
local currentAnimTrack = nil
local lastDirection = nil
local animator = nil
local humanoid = nil
local rootPart = nil
local wasShiftLockOn = false

-- Initialize _G variables (safety check)
if _G.IsCrouching == nil then _G.IsCrouching = false end
if _G.IsLanding == nil then _G.IsLanding = false end
if _G.IsFrozen == nil then _G.IsFrozen = false end
if _G.IsRolling == nil then _G.IsRolling = false end

-- Helper function to check if sprinting
local function isSprinting()
	return _G.IsSprinting or false
end

-- Helper function to check if can play directional animations
local function canPlayAnimations()
	return not isSprinting()
	   and not (_G.IsCrouching or false)
	   and not (_G.IsLanding or false)
	   and not (_G.IsFrozen or false)
	   and not (_G.IsRolling or false)
end

-- Animation objects (created upfront)
local animBackward = Instance.new("Animation")
animBackward.AnimationId = ANIM_BACKWARD

local animRight = Instance.new("Animation")
animRight.AnimationId = ANIM_RIGHT

local animLeft = Instance.new("Animation")
animLeft.AnimationId = ANIM_LEFT

-- Loaded animation tracks
local loadedTracks = {
	backward = nil,
	right = nil,
	left = nil
}

-- Find and require SmoothShiftLock module
local function getShiftLockModule()
	-- Search in PlayerScripts (copied here at runtime)
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

-- Update character variables
local function refreshCharacterVariables()
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
	
	return humanoid ~= nil and rootPart ~= nil and animator ~= nil
end

-- Stop all directional animations
local function stopAllDirectionalAnimations()
	for _, track in pairs(loadedTracks) do
		if track and track.IsPlaying then
			track:Stop(0.1)
		end
	end
	currentAnimTrack = nil
	lastDirection = nil
end

-- No longer needed - we don't restart Animate script anymore
-- The default Animate script will handle animations naturally when directional animations stop

-- Preload animations
local function preloadAnimations()
	if not animator then return end
	
	-- Clear old tracks first to prevent memory leaks
	for key, track in pairs(loadedTracks) do
		if track then
			track:Stop()
			track:Destroy()
			loadedTracks[key] = nil
		end
	end
	
	-- Use Action4 (highest priority) to override default Animate script
	loadedTracks.backward = animator:LoadAnimation(animBackward)
	loadedTracks.backward.Priority = Enum.AnimationPriority.Action4
	
	loadedTracks.right = animator:LoadAnimation(animRight)
	loadedTracks.right.Priority = Enum.AnimationPriority.Action4
	
	loadedTracks.left = animator:LoadAnimation(animLeft)
	loadedTracks.left.Priority = Enum.AnimationPriority.Action4
end

-- Play animation
local function playDirectionalAnimation(direction)
	if not animator then return end
	
	-- Load track if not loaded
	if not loadedTracks[direction] then
		preloadAnimations()
	end
	
	local track = loadedTracks[direction]
	if not track then return end
	
	-- Don't replay if same animation is already playing
	if currentAnimTrack and currentAnimTrack.IsPlaying and lastDirection == direction then
		return
	end
	
	stopAllDirectionalAnimations()
	
	currentAnimTrack = track
	currentAnimTrack:Play(0.15)
	
	lastDirection = direction
end

-- Calculate movement direction (simplified - direct key check)
local function getMovementDirection()
	-- Direct key checks - more reliable than vector math
	local isW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local isS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local isA = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local isD = UserInputService:IsKeyDown(Enum.KeyCode.D)
	
	-- Priority: backward > right > left (when multiple keys pressed)
	-- This matches the animation priority order
	if isS then
		return "backward"
	elseif isD then
		return "right"
	elseif isA then
		return "left"
	end
	
	return nil
end

-- Main loop
local function onUpdate()
	-- Get ShiftLock module if not yet acquired
	if not SmoothShiftLock then
		SmoothShiftLock = getShiftLockModule()
	end
	
	-- Stop animation and exit if ShiftLock is off
	if not SmoothShiftLock or not SmoothShiftLock.Enabled then
		if wasShiftLockOn then
			-- ShiftLock was just turned off: stop all directional anims
			-- Don't restart Animate script - let it handle animations naturally
			stopAllDirectionalAnimations()
			wasShiftLockOn = false
		elseif currentAnimTrack and currentAnimTrack.IsPlaying then
			stopAllDirectionalAnimations()
		end
		return
	end
	
	wasShiftLockOn = true
	
	-- Check character variables
	if not humanoid or not rootPart then
		if not refreshCharacterVariables() then
			return
		end
	end
	
	-- Don't play animations if sprinting or other states are active
	if not canPlayAnimations() then
		if currentAnimTrack and currentAnimTrack.IsPlaying then
			stopAllDirectionalAnimations()
		end
		return
	end
	
	-- Get movement direction
	local direction = getMovementDirection()
	
	-- Play animation based on direction
	if direction == "backward" then
		playDirectionalAnimation("backward")
	elseif direction == "right" then
		playDirectionalAnimation("right")
	elseif direction == "left" then
		playDirectionalAnimation("left")
	else
		-- Stop animation if no movement
		if currentAnimTrack and currentAnimTrack.IsPlaying then
			stopAllDirectionalAnimations()
		end
	end
end

-- Update variables when character is added
LocalPlayer.CharacterAdded:Connect(function()
	wasShiftLockOn = false
	if refreshCharacterVariables() then
		preloadAnimations()
	end
end)

-- Get variables on initial load
if refreshCharacterVariables() then
	preloadAnimations()
end

-- Run on RenderStepped
RunService.RenderStepped:Connect(onUpdate)