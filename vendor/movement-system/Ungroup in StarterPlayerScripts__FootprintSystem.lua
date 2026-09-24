--This Movement System made by Chornovose/@KMB910285

-- Footprint System
-- Footprints are created while walking

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Settings
local FOOTPRINT_SIZE = Vector3.new(1, 0.05, 1)
local FOOTPRINT_LIFETIME = 3 -- Seconds
local FOOTPRINT_FADE_TIME = 1 -- Fade duration

-- Footprint intervals by state (seconds)
local WALK_INTERVAL = 0.5 -- Walking
local SPRINT_INTERVAL = 0.35 -- Sprinting
local CROUCH_INTERVAL = 0.75 -- Crouching

local UserInputService = game:GetService("UserInputService")

-- State variables
local lastFootprintTime = 0
local isLeftFoot = true
local footprints = {}
local wasInAir = false
local landingCooldown = 0 -- Cooldown after landing
local LANDING_COOLDOWN_DURATION = 0.5 -- Wait duration after landing

-- Leg parts
local leftLeg = nil
local rightLeg = nil

-- Raycast parameters (reusable)
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	raycastParams.FilterDescendantsInstances = {character}
end

-- Find leg parts
local function findLegParts()
	leftLeg = nil
	rightLeg = nil
	
	-- For R15 character
	local leftFoot = character:FindFirstChild("LeftFoot", true)
	local rightFoot = character:FindFirstChild("RightFoot", true)
	
	if leftFoot and leftFoot:IsA("BasePart") then
		leftLeg = leftFoot
	end
	if rightFoot and rightFoot:IsA("BasePart") then
		rightLeg = rightFoot
	end
	
	-- Fallback for R6 character
	if not leftLeg then
		leftLeg = character:FindFirstChild("Left Leg")
	end
	if not rightLeg then
		rightLeg = character:FindFirstChild("Right Leg")
	end
end

-- Ground raycast - cast downward from given position
-- Returns: position (on ground surface), normal (ground direction) or nil
local function castToGround(fromPosition)
	updateRaycastFilter()
	local rayResult = workspace:Raycast(
		fromPosition,
		Vector3.new(0, -10, 0),
		raycastParams
	)
	if rayResult then
		return rayResult.Position, rayResult.Normal
	end
	return nil, nil
end

-- Create footprint - flush with ground surface
local function createFootprint(position, surfaceNormal, isLeft)
	if not position or not surfaceNormal then return nil end
	
	-- Footprint part
	local footprint = Instance.new("Part")
	footprint.Name = "Footprint"
	footprint.Size = FOOTPRINT_SIZE
	
	-- Create CFrame with UpVector = surfaceNormal (footprint lies flat on surface)
	local rightVector = surfaceNormal:Cross(rootPart.CFrame.LookVector)
	if rightVector.Magnitude < 0.01 then
		rightVector = surfaceNormal:Cross(Vector3.new(0, 0, 1))
	end
	rightVector = rightVector.Unit
	local lookVector = rightVector:Cross(surfaceNormal).Unit

	local footprintCFrame = CFrame.fromMatrix(position, rightVector, surfaceNormal, -lookVector)
	-- Offset slightly above ground so footprint is visible
	footprintCFrame = footprintCFrame + surfaceNormal * 0.1
	-- Slight rotation angle (left/right foot)
	footprintCFrame = footprintCFrame * CFrame.Angles(0, math.rad(isLeft and -5 or 5), 0)
	
	footprint.CFrame = footprintCFrame
	footprint.Anchored = true
	footprint.CanCollide = false
	footprint.Material = Enum.Material.Slate
	footprint.Color = Color3.fromRGB(60, 50, 40)
	footprint.Transparency = 0.3
	footprint.Parent = workspace
	
	-- Fade animation
	task.delay(FOOTPRINT_LIFETIME - FOOTPRINT_FADE_TIME, function()
		if not footprint or not footprint.Parent then return end
		
		local startTransparency = footprint.Transparency
		local startTime = tick()
		
		while footprint and footprint.Parent do
			local elapsed = tick() - startTime
			local progress = math.min(elapsed / FOOTPRINT_FADE_TIME, 1)
			
			footprint.Transparency = startTransparency + (1 - startTransparency) * progress
			
			if progress >= 1 then
				footprint.Parent = nil
				break
			end
			
			task.wait(0.05)
		end
	end)
	
	return footprint
end

-- Get foot position (from actual leg part) and cast to ground
local function getFootPositionAndNormal(isLeft)
	local legPart = isLeft and leftLeg or rightLeg
	local footXZ
	
	if legPart and legPart:IsA("BasePart") then
		local legPos = legPart.Position
		footXZ = Vector3.new(legPos.X, rootPart.Position.Y, legPos.Z)
	else
		-- Fallback: Calculate from HumanoidRootPart
		local offset = Vector3.new(isLeft and -1.5 or 1.5, 0, 0)
		footXZ = rootPart.CFrame:PointToWorldSpace(offset)
	end
	
	-- Cast downward from foot position, find actual ground surface
	local groundPos, groundNormal = castToGround(footXZ)
	return groundPos, groundNormal
end

-- Check if on ground - using Humanoid state (more reliable)
local function isOnGround()
	if humanoid then
		local state = humanoid:GetState()
		return state == Enum.HumanoidStateType.Landed
			or state == Enum.HumanoidStateType.Running
			or state == Enum.HumanoidStateType.RunningNoPhysics
			or state == Enum.HumanoidStateType.Climbing
			or state == Enum.HumanoidStateType.Seated
			or state == Enum.HumanoidStateType.StrafingNoPhysics
	end
	return false
end

-- Main loop
RunService.Heartbeat:Connect(function(deltaTime)
	-- Update character variables
	if not character or not character.Parent then
		character = player.Character
		if character then
			humanoid = character:FindFirstChild("Humanoid")
			rootPart = character:FindFirstChild("HumanoidRootPart")
			findLegParts()
		end
		return
	end
	
	if not humanoid or not rootPart then return end
	
	-- Check leg parts
	if not leftLeg or not rightLeg then
		findLegParts()
	end
	
	-- Check if moving
	local isMoving = humanoid.MoveDirection.Magnitude > 0.1
	
	-- Check if on ground (no footprints in air)
	local onGround = isOnGround()
	
	-- Landing check - transitioned from air to ground
	if wasInAir and onGround then
		-- Create footprint under both feet (flush with ground surface)
		local leftPos, leftNormal = getFootPositionAndNormal(true)
		local rightPos, rightNormal = getFootPositionAndNormal(false)
		
		createFootprint(leftPos, leftNormal, true)
		createFootprint(rightPos, rightNormal, false)
		
		-- Start landing cooldown
		landingCooldown = LANDING_COOLDOWN_DURATION
		lastFootprintTime = tick()
		
		wasInAir = false
		return
	end
	
	-- Update in-air state
	wasInAir = not onGround
	
	-- Exit if in air or not moving
	if not onGround or not isMoving then
		return
	end
	
	-- Wait if landing cooldown is active
	if landingCooldown > 0 then
		landingCooldown = landingCooldown - deltaTime
		return
	end
	
	-- Determine state
	local isCrouching = _G.IsCrouching or false
	local isSprinting = false
	
	-- Sprint check (Shift held and not crouching)
	if not isCrouching then
		local isShiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) 
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		isSprinting = isShiftHeld
	end
	
	-- Select interval based on state
	local currentInterval
	if isCrouching then
		currentInterval = CROUCH_INTERVAL
	elseif isSprinting then
		currentInterval = SPRINT_INTERVAL
	else
		currentInterval = WALK_INTERVAL
	end
	
	local currentTime = tick()
	
	-- Footprint interval check
	if currentTime - lastFootprintTime >= currentInterval then
		lastFootprintTime = currentTime
		
		-- Get foot position (flush with ground surface)
		local footPos, footNormal = getFootPositionAndNormal(isLeftFoot)
		
		-- Create footprint
		createFootprint(footPos, footNormal, isLeftFoot)
		
		-- Alternate foot
		isLeftFoot = not isLeftFoot
	end
end)

-- When character respawns
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	
	-- Find leg parts
	findLegParts()
	
	-- Reset state
	lastFootprintTime = 0
	isLeftFoot = true
	wasInAir = false
	landingCooldown = 0
end)

-- Initial load
findLegParts()