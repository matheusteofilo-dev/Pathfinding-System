--!nonstrict

local ServerScriptService = game:GetService("ServerScriptService")

local NPCSystem = require(ServerScriptService:WaitForChild("NPCSystem"))

local ok, err = pcall(NPCSystem.Start)
if not ok then
	warn(err)
end
