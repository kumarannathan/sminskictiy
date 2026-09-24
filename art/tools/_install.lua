_G.SR_sync = function()
	local HttpService = game:GetService("HttpService")
	local prev = HttpService.HttpEnabled
	HttpService.HttpEnabled = true
	local function get(f)
		return HttpService:GetAsync("http://127.0.0.1:8765/" .. f .. "?t=" .. os.clock(), true)
	end
	local ok, err = pcall(function()
		local SES = game:GetService("ScriptEditorService")
		local function put(parent, name, class, file)
			local s = parent:FindFirstChild(name)
			if s and s.ClassName ~= class then s:Destroy() s = nil end
			if not s then
				s = Instance.new(class)
				s.Name = name
				s.Parent = parent
			end
			local src = get(file)
			SES:UpdateSourceAsync(s, function() return src end)
			return s
		end
		local shared = game.ReplicatedStorage:FindFirstChild("SminskiShared") or Instance.new("Folder")
		shared.Name = "SminskiShared"
		shared.Parent = game.ReplicatedStorage
		for _, m in { "Config", "Rigs", "Places", "RigMeshes", "Art", "ParkRules", "Props", "PropMeshes" } do
			put(shared, m, "ModuleScript", m .. ".lua")
		end
		local server = put(game.ServerScriptService, "SminskiServer", "Script", "SminskiServer.server.lua")
		put(server, "Matchmaking", "ModuleScript", "Matchmaking.lua")
		put(server, "Survival", "ModuleScript", "Survival.lua")
		local main = put(game.StarterPlayer.StarterPlayerScripts, "SminskiRunner", "LocalScript", "SminskiRunner.client.lua")
		for _, m in { "Models", "World", "Audio", "UI", "Multiplayer", "Hub", "HubSets", "Park" } do
			put(main, m, "ModuleScript", m .. ".lua")
		end
	end)
	HttpService.HttpEnabled = prev
	return ok and "synced" or ("sync failed: " .. tostring(err))
end

_G.SR_preview = function()
	if _G.SR then pcall(_G.SR.cleanup) end
	_G.SR = nil
	for _, n in { "RunnerWorld", "RunnerActors", "SminskiHub", "SminskiHubActors", "SminskiPark", "SminskiParkActors" } do local x = workspace:FindFirstChild(n) if x then x:Destroy() end end
	for _, n in { "SminskiRunnerUI", "SminskiHubUI", "SminskiParkUI" } do local g = game.StarterGui:FindFirstChild(n) if g then g:Destroy() end end
	for _, n in { "SminskiAudio", "SminskiRunnerSFX" } do local x = game.SoundService:FindFirstChild(n) if x then x:Destroy() end end
	local fx = game.Lighting:FindFirstChild("SminskiRunFX") if fx then fx:Destroy() end
	local main = game.StarterPlayer.StarterPlayerScripts.SminskiRunner
	local clone = main:Clone()
	_G.SR_ROOT = clone
	local shared = game.ReplicatedStorage.SminskiShared
	local originals = {}
	for _, m in shared:GetChildren() do
		if m:IsA("ModuleScript") then
			local c = m:Clone()
			originals[c] = m
			m.Parent = nil
			c.Parent = shared
		end
	end
	local f, err = loadstring(main.Source)
	local ok, res
	if f then ok, res = pcall(f) end
	for c, m in originals do
		c.Parent = nil
		m.Parent = shared
		c:Destroy()
	end
	if not f then return "compile: " .. err end
	if not ok then return "runtime: " .. tostring(res) end
	_G.SR = res
	return "preview ok"
end

return "installed"