--!nonstrict

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local NPCSystem = require(ServerScriptService:WaitForChild("NPCSystem"))

local scene = Workspace:WaitForChild("NPCTestScene", 30)
local button = scene and scene:WaitForChild("NoiseButton", 30)
local prompt = button and button:WaitForChild("ProximityPrompt", 30)
if not prompt then
	return
end

prompt.Triggered:Connect(function()
	local heard = NPCSystem.EmitNoise(button.Position, 20)
	print(("[NoiseExample] noise radius 20 heard by %s NPC(s)"):format(tostring(heard)))
end)
