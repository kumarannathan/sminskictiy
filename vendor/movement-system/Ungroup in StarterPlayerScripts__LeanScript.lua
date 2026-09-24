--This Movement System made by Chornovose/@KMB910285

local RunService = game:GetService("RunService")

local plr = game.Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

local rootJoint = hrp.RootJoint
local rootC0 = rootJoint.C0

local tilt = CFrame.new()
local maxTilt = 3

RunService.RenderStepped:Connect(function(delta)
	
	local moveDirection = hrp.CFrame:VectorToObjectSpace(char.Humanoid.MoveDirection)
	
	tilt = tilt:Lerp(CFrame.Angles(math.rad(moveDirection.Z) * maxTilt, math.rad(-moveDirection.X) * maxTilt, 0), 10 * delta)
	
	rootJoint.C0 = rootC0 * tilt
end)