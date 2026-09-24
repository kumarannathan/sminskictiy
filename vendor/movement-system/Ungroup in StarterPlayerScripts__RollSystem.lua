--This Movement System made by Chornovose/@KMB910285

-- Roll System
-- Press Q to roll

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- Settings
local ROLL_DURATION = 0.5      -- Roll duration (seconds)
local ROLL_DISTANCE = 20        -- Roll distance (studs)
local COOLDOWN = 1             -- Cooldown duration (seconds)

-- Animation IDs
local ROLL_ANIM_ID = "rbxassetid://78160582722745"  -- Roll animation (use your own ID)

-- Variables
local isRolling = false
local canRoll = true
local humanoid = nil
local animator = nil
local character = nil
local rollTrack = nil

-- Global access
_G.IsRolling = false

-- Animation object
local animRoll = Instance.new("Animation")
animRoll.AnimationId = ROLL_ANIM_ID

-- Update character variables
local function refreshCharacter()
	character = LocalPlayer.Character
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

-- Load animation
local function loadAnimation()
	if not animator then return end
	rollTrack = animator:LoadAnimation(animRoll)
	rollTrack.Priority = Enum.AnimationPriority.Action
end

-- Perform roll
local function performRoll()
	if isRolling then return end
	if not canRoll then return end
	if not refreshCharacter() then return end
	
	-- Check other systems
	if _G.IsCrouching then return end
	if _G.IsLanding or _G.IsFrozen then return end
	
	-- Load animation (first time)
	if not rollTrack then
		loadAnimation()
	end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	isRolling = true
	canRoll = false
	_G.IsRolling = true
	
	-- Completely disable movement
	humanoid.WalkSpeed = 0
	
	-- Play roll animation
	if rollTrack then
		rollTrack:Play(0.1)
	end
	
	-- Move forward (Tween)
	local lookVector = hrp.CFrame.LookVector
	local startPos = hrp.CFrame
	local endPos = startPos + (lookVector * ROLL_DISTANCE)
	
	local tweenInfo = TweenInfo.new(ROLL_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local tween = TweenService:Create(hrp, tweenInfo, {CFrame = endPos})
	tween:Play()
	
	-- When roll ends
	task.delay(ROLL_DURATION, function()
		isRolling = false
		_G.IsRolling = false
		
		if rollTrack and rollTrack.IsPlaying then
			rollTrack:Stop(0.1)
		end
		
		-- Restore speed
		if humanoid then
			humanoid.WalkSpeed = 16
		end
		
		-- Cooldown
		task.wait(COOLDOWN)
		canRoll = true
	end)
end

-- Key listener
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.Q then
		performRoll()
	end
end)

-- Reset when character spawns
LocalPlayer.CharacterAdded:Connect(function()
	isRolling = false
	canRoll = true
	rollTrack = nil
	_G.IsRolling = false
end)