-- Dump every script out of a .rbxl into a directory, one file per script,
-- named by its full path so nothing collides.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local placePath = process.args[1]
local outDir = process.args[2]

local game = roblox.deserializePlace(fs.readFile(placePath))

if fs.isDir(outDir) then fs.removeDir(outDir) end
fs.writeDir(outDir)

local KINDS = { Script = true, LocalScript = true, ModuleScript = true }
local manifest = {}
local n = 0

local function walk(inst, path)
	for _, child in inst:GetChildren() do
		local p = path .. "/" .. child.Name
		if KINDS[child.ClassName] then
			n += 1
			local flat = p:sub(2):gsub("/", "__")
			local src = child.Source or ""
			fs.writeFile(outDir .. "/" .. flat .. ".lua", src)
			table.insert(manifest, string.format("%-14s %6d  %s", child.ClassName, #src, p:sub(2)))
		end
		local ok = pcall(function() return child:GetChildren() end)
		if ok then walk(child, p) end
	end
end

for _, svc in { "ServerScriptService", "ReplicatedStorage", "ReplicatedFirst",
	"StarterPlayer", "StarterGui", "Workspace", "ServerStorage", "Lighting", "SoundService" } do
	local ok, s = pcall(function() return game:GetService(svc) end)
	if ok and s then walk(s, "/" .. svc) end
end

table.sort(manifest)
fs.writeFile(outDir .. "/_manifest.txt", table.concat(manifest, "\n"))
print(string.format("%d scripts -> %s", n, outDir))
