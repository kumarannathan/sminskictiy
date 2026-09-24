--This Movement System made by Chornovose/@KMB910285

-- Stamina Sprint System
-- Press Shift to sprint, stamina drains and regenerates

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local SmoothShiftLock = nil

-- Settings
local MAX_STAMINA = 100
local STAMINA_DRAIN_RATE = 15  -- How much drains per second
local STAMINA_REGEN_RATE = 10 -- How much regenerates per second
local STAMINA_REGEN_DELAY = 1 -- Seconds before regen starts after stopping sprint
local SPRINT_SPEED = 25       -- Sprint speed
local WALK_SPEED = 15        -- Normal walk speed

-- FOV Settings
local NORMAL_FOV = 70        -- Default FOV
local SPRINT_FOV = 85         -- FOV while sprinting
local FOV_TWEEN_TIME = 0.3   -- Time to transition FOV

-- Animation IDs
local SPRINT_FORWARD = "rbxassetid://90406132115652"  -- Forward (W)
local SPRINT_BACKWARD = "rbxassetid://88115205003597"  -- Backward (S)
local SPRINT_RIGHT = "rbxassetid://89455067218226"     -- Right (D)
local SPRINT_LEFT = "rbxassetid://88141253804439"      -- Left (A)

-- Variables
local currentStamina = MAX_STAMINA
local isSprinting = false
local isShiftHeld = false
local lastSprintTime = 0
local staminaRegenTimer = 0

-- Initialize _G variables (safety check)
if _G.IsCrouching == nil then _G.IsCrouching = false end
if _G.IsLanding == nil then _G.IsLanding = false end
if _G.IsFrozen == nil then _G.IsFrozen = false end
if _G.IsRolling == nil then _G.IsRolling = false end
if _G.IsSprinting == nil then _G.IsSprinting = false end

-- Helper function to safely check _G variables
local function canSprint()
	return not (_G.IsCrouching or false)
	   and not (_G.IsLanding or false)
	   and not (_G.IsFrozen or false)
	   and not (_G.IsRolling or false)
end

-- Character variables
local humanoid = nil
local rootPart = nil
local animator = nil
local sprintAnimTrack = nil

-- UI Variables
local staminaGui = nil
local staminaBar = nil
local staminaBackground = nil

-- Animation objects
local animForward = Instance.new("Animation")
animForward.AnimationId = SPRINT_FORWARD

local animBackward = Instance.new("Animation")
animBackward.AnimationId = SPRINT_BACKWARD

local animRight = Instance.new("Animation")
animRight.AnimationId = SPRINT_RIGHT

local animLeft = Instance.new("Animation")
animLeft.AnimationId = SPRINT_LEFT

-- Loaded animation tracks
local loadedTracks = {
	forward = nil,
	backward = nil,
	right = nil,
	left = nil
}

-- Current direction
local currentDirection = nil

-- Create Stamina Bar UI
local function createStaminaUI()
	-- Main GUI
	staminaGui = Instance.new("ScreenGui")
	staminaGui.Name = "StaminaGui"
	staminaGui.ResetOnSpawn = false
	staminaGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	staminaGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	
	-- Background frame
	local frame = Instance.new("Frame")
	frame.Name = "StaminaFrame"
	frame.Size = UDim2.new(0, 200, 0, 20)
	frame.Position = UDim2.new(0.5, -100, 0.9, -30)
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	frame.BorderSizePixel = 2
	frame.BorderColor3 = Color3.fromRGB(80, 80, 80)
	frame.Parent = staminaGui
	
	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	
	-- Stamina bar (inner)
	staminaBar = Instance.new("Frame")
	staminaBar.Name = "StaminaBar"
	staminaBar.Size = UDim2.new(1, 0, 1, 0)
	staminaBar.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	staminaBar.BorderSizePixel = 0
	staminaBar.Parent = frame
	
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 4)
	barCorner.Parent = staminaBar
	
	-- Stamina text
	local label = Instance.new("TextLabel")
	label.Name = "StaminaText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = frame
	
	staminaBackground = frame
end

-- Update stamina bar
local function updateStaminaUI()
	if not staminaBar then return end
	
	local percent = currentStamina / MAX_STAMINA
	staminaBar.Size = UDim2.new(percent, 0, 1, 0)
	
	-- Change color based on stamina amount
	if percent > 0.6 then
		staminaBar.BackgroundColor3 = Color3.fromRGB(50, 200, 50)  -- Green
	elseif percent > 0.3 then
		staminaBar.BackgroundColor3 = Color3.fromRGB(200, 200, 50)  -- Yellow
	else
		staminaBar.BackgroundColor3 = Color3.fromRGB(200, 50, 50)  -- Red
	end
end

-- Update character variables
local function refreshCharacterVariables()
	local character = LocalPlayer.Character
	if not character then return false end
	
	-- Use WaitForChild for reliable loading
	humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 1)
	end
	
	rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		rootPart = character:WaitForChild("HumanoidRootPart", 1)
	end
	
	if humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			-- Wait for Animator to be created by Roblox
			animator = humanoid:WaitForChild("Animator", 1)
			if not animator then
				-- Create if still doesn't exist
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
		end
	end
	
	return humanoid ~= nil and rootPart ~= nil and animator ~= nil
end

-- Preload animations
local function preloadAnimations()
	if not animator then return false end
	
	-- Clear old tracks first
	for key, track in pairs(loadedTracks) do
		if track then
			track:Stop()
			track:Destroy()
			loadedTracks[key] = nil
		end
	end
	
	local success, err = pcall(function()
		-- Use Action4 (highest priority) to override everything including default Animate script
		loadedTracks.forward = animator:LoadAnimation(animForward)
		loadedTracks.forward.Priority = Enum.AnimationPriority.Action4
		
		loadedTracks.backward = animator:LoadAnimation(animBackward)
		loadedTracks.backward.Priority = Enum.AnimationPriority.Action4
		
		loadedTracks.right = animator:LoadAnimation(animRight)
		loadedTracks.right.Priority = Enum.AnimationPriority.Action4
		
		loadedTracks.left = animator:LoadAnimation(animLeft)
		loadedTracks.left.Priority = Enum.AnimationPriority.Action4
	end)
	
	return success
end

-- Start sprint animation
local function startSprintAnimation(direction)
	if not animator then 
		-- Try to get animator
		refreshCharacterVariables()
		if not animator then return end
	end
	
	-- Load tracks if not loaded
	if not loadedTracks[direction] then
		if not preloadAnimations() then return end
	end
	
	local track = loadedTracks[direction]
	if not track then return end
	
	-- Don't replay if same animation is already playing
	if sprintAnimTrack and sprintAnimTrack.IsPlaying and currentDirection == direction then
		return
	end
	
	-- Stop previous animation
	if sprintAnimTrack and sprintAnimTrack.IsPlaying then
		sprintAnimTrack:Stop(0.15)
	end
	
	sprintAnimTrack = track
	sprintAnimTrack:Play(0.15)
	currentDirection = direction
end

-- Stop sprint animation
local function stopSprintAnimation()
	if sprintAnimTrack then
		if sprintAnimTrack.IsPlaying then
			sprintAnimTrack:Stop(0.15)
		end
		sprintAnimTrack = nil
	end
	currentDirection = nil
end

-- Start sprinting
local function startSprinting()
	if isSprinting then return end
	if currentStamina <= 0 then return end
	if not humanoid then return end
	if not canSprint() then return end  -- Check all _G variables safely
	
	isSprinting = true
	_G.IsSprinting = true  -- Notify other scripts
	humanoid.WalkSpeed = SPRINT_SPEED
	-- Don't stop Animate script - let sprint animations override walk naturally
	
	-- Increase FOV
	local camera = workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = SPRINT_FOV
		}):Play()
	end
end

-- Stop sprinting
local function stopSprinting()
	if not isSprinting then return end
	
	isSprinting = false
	_G.IsSprinting = false  -- Notify other scripts
	if humanoid then
		humanoid.WalkSpeed = WALK_SPEED
	end
	stopSprintAnimation()
	-- Don't restart Animate script - it never stopped
	
	-- Restore FOV
	local camera = workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = NORMAL_FOV
		}):Play()
	end
end

-- When Shift key is pressed
local function onShiftDown()
	isShiftHeld = true
	if currentStamina > 0 then
		startSprinting()
	end
end

-- When Shift key is released
local function onShiftUp()
	isShiftHeld = false
	stopSprinting()
	lastSprintTime = tick()
end

-- Key listeners
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onShiftDown()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onShiftUp()
	end
end)

-- Find and require SmoothShiftLock module
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

-- Get movement direction (simplified - direct key check)
local function getMovementDirection()
	-- Direct key checks - more reliable than vector math
	local isW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local isA = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local isS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local isD = UserInputService:IsKeyDown(Enum.KeyCode.D)
	
	-- Check if moving at all
	local isMoving = isW or isA or isS or isD
	if not isMoving then
		return nil, false
	end
	
	-- Priority: forward > backward > right > left (when multiple keys pressed)
	-- Forward is most important for sprint
	if isW then
		return "forward", true
	elseif isS then
		return "backward", true
	elseif isD then
		return "right", true
	elseif isA then
		return "left", true
	end
	
	return nil, false
end

-- Start sprinting
local function startSprinting()
	if isSprinting then return end
	if currentStamina <= 0 then return end
	if not humanoid then return end
	if not canSprint() then return end  -- Check all _G variables safely
	
	isSprinting = true
	_G.IsSprinting = true  -- Notify other scripts
	humanoid.WalkSpeed = SPRINT_SPEED
	-- Don't stop Animate script - let sprint animations override walk naturally
	
	-- Increase FOV
	local camera = workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = SPRINT_FOV
		}):Play()
	end
end

-- Stop sprinting
local function stopSprinting()
	if not isSprinting then return end
	
	isSprinting = false
	_G.IsSprinting = false  -- Notify other scripts
	if humanoid then
		humanoid.WalkSpeed = WALK_SPEED
	end
	stopSprintAnimation()
	-- Don't restart Animate script - it never stopped
	
	-- Restore FOV
	local camera = workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = NORMAL_FOV
		}):Play()
	end
end

-- When Shift key is pressed
local function onShiftDown()
	isShiftHeld = true
	if currentStamina > 0 then
		startSprinting()
	end
end

-- When Shift key is released
local function onShiftUp()
	isShiftHeld = false
	stopSprinting()
	lastSprintTime = tick()
end

-- Key listeners
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onShiftDown()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onShiftUp()
	end
end)

-- Find and require SmoothShiftLock module
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

-- Get movement direction (simplified - direct key check)
local function getMovementDirection()
	-- Direct key checks - more reliable than vector math
	local isW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local isA = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local isS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local isD = UserInputService:IsKeyDown(Enum.KeyCode.D)
	
	-- Check if moving at all
	local isMoving = isW or isA or isS or isD
	if not isMoving then
		return nil, false
	end
	
	-- Priority: forward > backward > right > left (when multiple keys pressed)
	-- Forward is most important for sprint
	if isW then
		return "forward", true
	elseif isS then
		return "backward", true
	elseif isD then
		return "right", true
	elseif isA then
		return "left", true
	end
	
	return nil, false
end

-- Main loop
local function onUpdate(deltaTime)
	-- Check character variables
	if not humanoid or not rootPart then
		if not refreshCharacterVariables() then
			return
		end
	end
	
	-- Get ShiftLock module if not yet acquired
	if not SmoothShiftLock then
		SmoothShiftLock = getShiftLockModule()
	end
	
	-- Don't play animations if ShiftLock is off
	local isShiftLockEnabled = SmoothShiftLock and SmoothShiftLock.Enabled
	
	local direction, moving = getMovementDirection()
	
	-- Stop sprinting if Shift held but not moving
	if isSprinting and not moving then
		stopSprinting()
		lastSprintTime = tick()
	end
	
	-- Start sprinting if Shift held and moving (unless crouch/landing/rolling is active)
	if isShiftHeld and moving and not isSprinting and currentStamina > 0 and canSprint() then
		startSprinting()
	end
	
	-- Drain stamina and play animation while sprinting (unless crouching)
	if isSprinting and canSprint() then
		-- When ShiftLock is OFF, always play forward animation regardless of direction
		-- When ShiftLock is ON, play directional animations
		if direction then
			if isShiftLockEnabled then
				-- ShiftLock ON: play directional animations
				startSprintAnimation(direction)
			else
				-- ShiftLock OFF: always play forward animation
				startSprintAnimation("forward")
			end
		end
		
		currentStamina = math.max(0, currentStamina - STAMINA_DRAIN_RATE * deltaTime)
		updateStaminaUI()
		
		-- Stop sprinting if stamina runs out
		if currentStamina <= 0 then
			stopSprinting()
			lastSprintTime = tick()
		end
	else
		-- Stamina regeneration
		local timeSinceSprint = tick() - lastSprintTime
		if timeSinceSprint >= STAMINA_REGEN_DELAY then
			currentStamina = math.min(MAX_STAMINA, currentStamina + STAMINA_REGEN_RATE * deltaTime)
			updateStaminaUI()
		end
	end
end

-- When character is added
LocalPlayer.CharacterAdded:Connect(function()
	-- Reset state
	currentStamina = MAX_STAMINA
	isSprinting = false
	isShiftHeld = false
	lastSprintTime = 0
	currentDirection = nil
	sprintAnimTrack = nil
	
	-- Refresh and preload after character is ready (WaitForChild handles timing)
	if refreshCharacterVariables() then
		preloadAnimations()
	end
	
	-- Create UI (only once)
	if not staminaGui then
		createStaminaUI()
	end
	updateStaminaUI()
end)

-- Initial load
if refreshCharacterVariables() then
	preloadAnimations()
	createStaminaUI()
	updateStaminaUI()
end

-- Run on RenderStepped
RunService.RenderStepped:Connect(onUpdate)