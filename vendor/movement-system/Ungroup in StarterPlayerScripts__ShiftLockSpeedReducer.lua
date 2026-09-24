--This Movement System made by Chornovose/@KMB910285

-- ShiftLock Speed Reducer
-- Reduces speed by 4 when going left/right, by 8 when going backward while ShiftLock is on

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local SmoothShiftLock = nil

-- Settings
local WALK_SPEED = 15
local CROUCH_SPEED = 10       -- Crouch speed (must match CrouchSystem)
local CROUCH_SHIFTLOCK_SPEED = 10  -- Crouch speed (ShiftLock on)
local SPRINT_SPEED = 25      -- Sprint speed (must match StaminaSprintSystem)
local LEAN_SPEED_REDUCTION = 4    -- Speed reduction when going left/right
local BACKWARD_SPEED_REDUCTION = 8 -- Speed reduction when going backward

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

-- Calculate movement direction (based on camera direction)
local function getMovementDirection(rootPart)
	if not rootPart then return nil end
	
	-- Check pressed keys
	local isW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local isS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local isA = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local isD = UserInputService:IsKeyDown(Enum.KeyCode.D)
	
	-- No keys pressed
	if not isW and not isS and not isA and not isD then
		return nil
	end
	
	-- Get camera directions
	local camera = workspace.CurrentCamera
	local lookVector, rightVector
	
	if camera then
		-- Normalize on horizontal plane (zero out Y component)
		lookVector = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
		rightVector = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z).Unit
	else
		lookVector = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
		rightVector = Vector3.new(rootPart.CFrame.RightVector.X, 0, rootPart.CFrame.RightVector.Z).Unit
	end
	
	-- Build movement vector
	local moveVector = Vector3.new(0, 0, 0)
	
	if isW then
		moveVector = moveVector + lookVector
	end
	if isS then
		moveVector = moveVector - lookVector
	end
	if isA then
		moveVector = moveVector - rightVector
	end
	if isD then
		moveVector = moveVector + rightVector
	end
	
	-- No movement
	if moveVector.Magnitude < 0.1 then
		return nil
	end
	
	moveVector = moveVector.Unit
	
	-- Determine direction (priority: backward > left/right > forward)
	local dotForward = moveVector:Dot(lookVector)
	local dotRight = moveVector:Dot(rightVector)
	
	-- Backward has highest priority
	if dotForward < -0.5 then
		return "backward"
	elseif math.abs(dotRight) > 0.5 then
		-- Right or left
		if dotRight > 0 then
			return "right"
		else
			return "left"
		end
	elseif dotForward > 0.5 then
		return "forward"
	end
	
	return "forward"
end

-- Previous ShiftLock state
local wasShiftLockEnabled = false

-- Track if we modified speed so we can restore properly
local lastAppliedSpeed = nil

-- Main loop
local function onUpdate()
	-- Get ShiftLock module
	if not SmoothShiftLock then
		SmoothShiftLock = getShiftLockModule()
	end
	
	local character = LocalPlayer.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not rootPart then return end
	
	-- Restore speed to normal if ShiftLock is off
	if not SmoothShiftLock or not SmoothShiftLock.Enabled then
		if wasShiftLockEnabled then
			-- Restore speed based on current state
			local isCrouching = _G.IsCrouching
			local isShiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) 
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			local isSprinting = isShiftHeld and not isCrouching
			
			if isCrouching then
				humanoid.WalkSpeed = CROUCH_SPEED
			elseif isSprinting then
				humanoid.WalkSpeed = SPRINT_SPEED
			else
				humanoid.WalkSpeed = WALK_SPEED
			end
			
			wasShiftLockEnabled = false
			lastAppliedSpeed = nil
		end
		return
	end
	
	wasShiftLockEnabled = true
	
	-- Get movement direction
	local direction = getMovementDirection(rootPart)
	
	-- Determine current state
	local isCrouching = _G.IsCrouching
	local isSprinting = false
	
	-- Check sprint state (Shift held and has stamina)
	local isShiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) 
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	
	if isShiftHeld and not isCrouching then
		isSprinting = true
	end
	
	-- Determine base speed (from other systems)
	local baseSpeed = WALK_SPEED
	if isCrouching then
		-- Different crouch speed when ShiftLock is on
		baseSpeed = CROUCH_SHIFTLOCK_SPEED
	elseif isSprinting then
		baseSpeed = SPRINT_SPEED
	end
	
	-- Adjust speed based on direction (apply reduction)
	local newSpeed = baseSpeed
	if direction == "left" or direction == "right" then
		newSpeed = baseSpeed - LEAN_SPEED_REDUCTION
	elseif direction == "backward" then
		newSpeed = baseSpeed - BACKWARD_SPEED_REDUCTION
	end
	
	-- Only apply if speed changed
	if lastAppliedSpeed ~= newSpeed then
		humanoid.WalkSpeed = newSpeed
		lastAppliedSpeed = newSpeed
	end
end

RunService.RenderStepped:Connect(onUpdate)