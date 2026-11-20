--!nonstrict

local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local config = require(ServerScriptService:WaitForChild("NPCSystem"):WaitForChild("config"))
if not (config.testScene and config.testScene.enabled) then
	return
end

local scene = Workspace:WaitForChild("NPCTestScene")
local door = scene:FindFirstChild("Door")
if door then
	local openY, closedY = door.Position.Y, 6
	task.spawn(function()
		while door.Parent do
			task.wait(8)
			door.Position = Vector3.new(door.Position.X, closedY, door.Position.Z)
			task.wait(6)
			door.Position = Vector3.new(door.Position.X, openY, door.Position.Z)
		end
	end)
end

local npcFolder = Workspace:WaitForChild("NPCs")
local templates = Instance.new("Folder")
templates.Name = "NPCTemplates"
templates.Parent = ServerStorage

local activate

local function watchDeath(model: Model, template: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.Died:Connect(function()
		task.wait(2)
		model:Destroy()
		local clone = template:Clone()
		clone.Parent = npcFolder
		activate(clone, template)
	end)
end

function activate(model: Model, template: Model)
	local tagValue = model:FindFirstChild("NPCTag")
	if tagValue and tagValue:IsA("StringValue") and tagValue.Value ~= "" then
		CollectionService:AddTag(model, tagValue.Value)
	end
	watchDeath(model, template)
end

for _, model in ipairs(npcFolder:GetChildren()) do
	task.spawn(function()
		local template = model:Clone()
		template.Parent = templates
		activate(model, template)
	end)
end
