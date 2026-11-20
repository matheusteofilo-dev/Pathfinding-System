--!nonstrict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local config = require(script.config)
local Validator = require(script.ConfigValidator)
local Rules = require(script.Rules)
local Vision = require(script.Vision)
local Controller = require(script.NPCController)
local NoiseService = require(script.NoiseService)
local DebugRenderer = require(script.DebugRenderer)
local MovementService = require(script.MovementService)

local NPCSystem = {}
NPCSystem.Rules = Rules
NPCSystem.config = config

local started = false
local profiles = {}
local controllers = {}
local byModel = {}
local pending = {}
local waiting = {}
local ended = setmetatable({}, { __mode = "k" })
local connections = {}
local debugRenderer = nil
local noiseService = nil
local lastAreaCheck = 0
local debugRemote = nil
local stopMovement = nil

local DEBUG_KEYS = { "enabled", "showVisionRays", "showSearchRays", "showLastSeenGhost", "showPaths", "showNoise", "showHearingRange", "showState", "showGaps" }

local function panelAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local ids = config.debug.panelUserIds
	return ids ~= nil and table.find(ids, player.UserId) ~= nil
end

local function debugState()
	local t = {}
	for _, k in ipairs(DEBUG_KEYS) do
		t[k] = config.debug[k] == true
	end
	return t
end

local function broadcastDebugState()
	if not debugRemote then
		return
	end
	local state = debugState()
	for _, plr in ipairs(Players:GetPlayers()) do
		if panelAuthorized(plr) then
			debugRemote:FireClient(plr, state)
		end
	end
end

local function log(msg: string)
	print("[NPCSystem] " .. msg)
end

local function removeController(ctrl, reason: string)
	if ctrl.destroyed then
		return
	end
	ctrl:destroy(reason)
	byModel[ctrl.model] = nil
	local idx = table.find(controllers, ctrl)
	if idx then
		table.remove(controllers, idx)
	end
end

local function resolveTag(model: Instance): string?
	local tags = {}
	for tag in pairs(profiles) do
		if CollectionService:HasTag(model, tag) then
			table.insert(tags, tag)
		end
	end
	table.sort(tags)
	if #tags > 1 then
		warn(("[NPCSystem] %s has multiple profile tags (%s); using '%s' (alphabetical order)."):format(model:GetFullName(), table.concat(tags, ", "), tags[1]))
	end
	return tags[1]
end

local tryRegister

local function createController(model: Model, tag: string)
	local humanoid = model:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(("[NPCSystem] %s has no Humanoid; NPC not registered."):format(model:GetFullName()))
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		warn(("[NPCSystem] %s has no PrimaryPart/HumanoidRootPart; NPC not registered."):format(model:GetFullName()))
		return
	end
	if byModel[model] or not model:IsDescendantOf(Workspace) or not CollectionService:HasTag(model, tag) then
		return
	end
	if humanoid.Health <= 0 then
		ended[model] = true
		return
	end

	local profile = profiles[tag]
	local ctrl = Controller.new(model, tag, profile, config, debugRenderer, humanoid, root)
	humanoid.WalkSpeed = profile.speed
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	table.insert(controllers, ctrl)
	byModel[model] = ctrl

	table.insert(ctrl.connections, humanoid.Died:Connect(function()
		ended[model] = true
		removeController(ctrl, "died")
	end))
	table.insert(ctrl.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			removeController(ctrl, "removed from workspace")
		end
	end))
	log(("registered %s (tag '%s')"):format(model:GetFullName(), tag))
end

function tryRegister(inst: Instance)
	if not started or byModel[inst] or pending[inst] or ended[inst] then
		return
	end
	if not inst:IsA("Model") then
		warn(("[NPCSystem] %s is tagged as an NPC but is not a Model."):format(inst:GetFullName()))
		return
	end
	local tag = resolveTag(inst)
	if not tag then
		return
	end
	if not inst:IsDescendantOf(Workspace) then
		if not waiting[inst] then
			waiting[inst] = inst.AncestryChanged:Connect(function()
				if inst:IsDescendantOf(Workspace) then
					waiting[inst]:Disconnect()
					waiting[inst] = nil
					tryRegister(inst)
				end
			end)
		end
		return
	end
	pending[inst] = true
	task.spawn(function()
		local ok, err = pcall(createController, inst, tag)
		pending[inst] = nil
		if not ok then
			warn(("[NPCSystem] failed to register %s: %s"):format(inst:GetFullName(), tostring(err)))
		end
	end)
end

local function onTagRemoved(inst: Instance, tag: string)
	if waiting[inst] and resolveTag(inst) == nil then
		waiting[inst]:Disconnect()
		waiting[inst] = nil
	end
	local ctrl = byModel[inst]
	if ctrl and ctrl.tag == tag then
		removeController(ctrl, "tag removed")
		ended[inst] = nil
		tryRegister(inst)
	end
end

local function step()
	local now = os.clock()
	local snapshot = table.clone(controllers)

	local area = config.managedArea
	local checkArea = area ~= nil and now - lastAreaCheck >= 2
	if checkArea then
		lastAreaCheck = now
	end

	local due = {}
	for _, ctrl in ipairs(snapshot) do
		if ctrl:isActive() then
			local ok, err = xpcall(ctrl.update, debug.traceback, ctrl, now)
			if not ok then
				warn(("[NPCSystem] update error on %s: %s"):format(ctrl.model.Name, tostring(err)))
			end
			if checkArea then
				local rel = ctrl.root.Position - area.center
				local half = area.size / 2
				if math.abs(rel.X) > half.X or math.abs(rel.Y) > half.Y or math.abs(rel.Z) > half.Z then
					removeController(ctrl, "left managed area")
					continue
				end
			end
			if now >= ctrl.nextPerceiveAt then
				table.insert(due, ctrl)
			end
		end
	end

	table.sort(due, function(a, b)
		return a.nextPerceiveAt < b.nextPerceiveAt
	end)
	local budget = math.min(#due, config.perception.maxPerceptionsPerStep)
	for i = 1, budget do
		local ctrl = due[i]
		ctrl.nextPerceiveAt = now + config.perception.updateInterval
		local ok, err = xpcall(ctrl.perceive, debug.traceback, ctrl, now)
		if not ok then
			warn(("[NPCSystem] perception error on %s: %s"):format(ctrl.model.Name, tostring(err)))
		end
	end

	debugRenderer:update(controllers)
end

function NPCSystem.Start()
	if started then
		return
	end
	local errors = Validator.validateGlobal(config)
	if #errors > 0 then
		error("[NPCSystem] invalid global configuration:\n  - " .. table.concat(errors, "\n  - "), 0)
	end

	for tag, raw in pairs(config.npcs) do
		local profile, perrors = Validator.validateProfile(tag, raw, config)
		if profile then
			profiles[tag] = profile
		else
			warn(("[NPCSystem] profile '%s' disabled:\n  - %s"):format(tostring(tag), table.concat(perrors, "\n  - ")))
		end
	end

	debugRenderer = DebugRenderer.new(config)
	Vision.debugFolder = debugRenderer.folder
	Workspace:SetAttribute("NPCDebug", config.debug.enabled)
	debugRenderer:setEnabled(config.debug.enabled)
	table.insert(connections, Workspace:GetAttributeChangedSignal("NPCDebug"):Connect(function()
		local on = Workspace:GetAttribute("NPCDebug") == true
		config.debug.enabled = on
		debugRenderer:setEnabled(on)
		broadcastDebugState()
	end))

	debugRemote = ReplicatedStorage:FindFirstChild("NPCDebugRemote")
	if debugRemote then
		table.insert(connections, debugRemote.OnServerEvent:Connect(function(player, key, value)
			if not panelAuthorized(player) then
				return
			end
			if key == "sync" then
				debugRemote:FireClient(player, debugState())
				return
			end
			if type(key) ~= "string" or type(value) ~= "boolean" or not table.find(DEBUG_KEYS, key) then
				return
			end
			if key == "enabled" then
				config.debug.enabled = value
				NPCSystem.SetDebug(value)
			else
				config.debug[key] = value
			end
			broadcastDebugState()
		end))
	else
		warn("[NPCSystem] NPCDebugRemote not found in ReplicatedStorage; the debug panel is disabled.")
	end

	noiseService = NoiseService.new(function()
		return controllers
	end, function(event)
		debugRenderer:addNoise(event)
	end)

	started = true

	stopMovement = MovementService.start(config, function(position, radius, tag)
		NPCSystem.EmitNoise(position, radius, { tag = tag })
	end)

	for tag in pairs(profiles) do
		table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(tryRegister))
		table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			onTagRemoved(inst, tag)
		end))
	end
	for tag in pairs(profiles) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			tryRegister(inst)
		end
	end
	table.insert(connections, RunService.Heartbeat:Connect(step))
	log("started")
end

function NPCSystem.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	if stopMovement then
		stopMovement()
		stopMovement = nil
	end
	for _, c in pairs(waiting) do
		c:Disconnect()
	end
	table.clear(waiting)
	for _, ctrl in ipairs(table.clone(controllers)) do
		removeController(ctrl, "system stopped")
	end
	debugRenderer:setEnabled(false)
	debugRenderer.folder:ClearAllChildren()
end

function NPCSystem.EmitNoise(position: Vector3, volume: number, options: { tag: string? }?): (number?, string?)
	if not started then
		warn("[NPCSystem] EmitNoise called before Start()")
		return nil, "not started"
	end
	local heard, reason = noiseService:emit(position, volume, options)
	if heard == nil then
		warn("[NPCSystem] EmitNoise rejected: " .. tostring(reason))
	end
	return heard, reason
end

function NPCSystem.SetDebug(enabled: boolean)
	Workspace:SetAttribute("NPCDebug", enabled == true)
end

function NPCSystem.IsDebugEnabled(): boolean
	return debugRenderer ~= nil and debugRenderer.enabled
end

function NPCSystem.GetController(model: Instance)
	return byModel[model]
end

function NPCSystem.GetControllers()
	return table.clone(controllers)
end

function NPCSystem.GetDebugStats()
	return debugRenderer and debugRenderer:stats() or nil
end

return NPCSystem
