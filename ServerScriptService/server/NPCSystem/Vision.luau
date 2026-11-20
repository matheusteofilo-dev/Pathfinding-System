--!nonstrict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Vision = {}

Vision.debugFolder = nil :: Instance?

function Vision.buildParams(model: Instance): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = false
	params.IgnoreWater = true
	local list = { model }
	if Vision.debugFolder then
		table.insert(list, Vision.debugFolder)
	end
	params.FilterDescendantsInstances = list
	return params
end

function Vision.getEye(ctrl): Vector3
	local cached = ctrl.eyeSource
	if cached == nil or cached.Parent == nil then
		cached = ctrl.model:FindFirstChild(ctrl.config.perception.eyeAttachmentName, true)
		if cached == nil or not cached:IsA("Attachment") then
			cached = ctrl.model:FindFirstChild("Head")
		end
		ctrl.eyeSource = cached
	end
	if cached then
		if cached:IsA("Attachment") then
			return cached.WorldPosition
		elseif cached:IsA("BasePart") then
			return cached.Position
		end
	end
	return ctrl.root.Position + ctrl.config.perception.eyeFallbackOffset
end

local function isCosmetic(inst: Instance): Instance?
	return inst:FindFirstAncestorWhichIsA("Accoutrement") or inst:FindFirstAncestorWhichIsA("Tool")
end

local function isEligibleBodyPart(inst: Instance, cfg): boolean
	if not inst:IsA("BasePart") then
		return false
	end
	if cfg.ignoredBodyParts[inst.Name] then
		return false
	end
	if inst.Transparency >= cfg.minVisibleTransparency then
		return false
	end
	if isCosmetic(inst) then
		return false
	end
	return true
end
Vision.isEligibleBodyPart = isEligibleBodyPart

local function fractionToWorld(part: BasePart, f: Vector3): Vector3
	local s = part.Size
	return part.CFrame:PointToWorldSpace(Vector3.new(f.X * s.X, f.Y * s.Y, f.Z * s.Z))
end

function Vision.getSamples(ctrl, character: Model): { any }
	local cfg = ctrl.config.perception
	local map = ctrl.profile.rigMap
	if map == nil then
		if character:FindFirstChild("UpperTorso") then
			map = cfg.rigs.R15
		elseif character:FindFirstChild("Torso") then
			map = cfg.rigs.R6
		end
	end
	local samples = {}
	if map then
		for partName, fractions in pairs(map) do
			local part = character:FindFirstChild(partName)
			if part and isEligibleBodyPart(part, cfg) then
				for i, f in ipairs(fractions) do
					table.insert(samples, { name = partName .. "#" .. i, part = part, position = fractionToWorld(part, f) })
				end
			end
		end
	end
	if #samples == 0 then
		if not ctrl.rigWarned then
			ctrl.rigWarned = true
			warn(("[NPCSystem] %s: rig of target '%s' not recognized as R15/R6; using generic per-part samples. Provide profile.rigMap for custom rigs."):format(ctrl.model:GetFullName(), character.Name))
		end
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") and isEligibleBodyPart(child, cfg) then
				table.insert(samples, { name = child.Name, part = child, position = child.Position })
			end
		end
	end
	return samples
end

local function castToSample(origin: Vector3, samplePos: Vector3, params: RaycastParams, character: Model, cfg)
	local direction = samplePos - origin
	local base = params.FilterDescendantsInstances
	local extended = nil
	local visible, finalPos, hitInst = false, samplePos, nil

	for _ = 0, cfg.maxSeeThroughRecasts do
		local result = Workspace:Raycast(origin, direction, params)
		if result == nil then
			visible, finalPos, hitInst = false, samplePos, nil
			break
		end
		local inst = result.Instance
		finalPos, hitInst = result.Position, inst
		local skip: Instance? = nil
		if inst:IsDescendantOf(character) then
			if isEligibleBodyPart(inst, cfg) then
				visible = true
				break
			end
			skip = isCosmetic(inst) or inst
		elseif inst:GetAttribute(cfg.seeThroughAttribute) == true or CollectionService:HasTag(inst, cfg.seeThroughAttribute) then
			skip = inst
		else
			visible = false
			break
		end
		if extended == nil then
			extended = table.clone(base)
		end
		table.insert(extended, skip)
		params.FilterDescendantsInstances = extended
		visible = false
	end

	if extended ~= nil then
		params.FilterDescendantsInstances = base
	end
	return visible, finalPos, hitInst
end

function Vision.scan(ctrl, opts)
	local cfg = ctrl.config.perception
	local origin = Vision.getEye(ctrl)
	local rootPos = ctrl.root.Position
	local fov, range = opts.fov, opts.range
	local cosHalf = if fov >= 360 then -2 else math.cos(math.rad(fov * 0.5))
	local look = ctrl.root.CFrame.LookVector
	local record = opts.record
	local rays = if record then {} else nil
	local results = {}
	local canTarget = ctrl.profile.canTarget

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and hrp and humanoid.Health > 0 and hrp:IsA("BasePart") then
			local allowed = true
			if canTarget then
				local ok, res = pcall(canTarget, player)
				allowed = ok and res == true
			end
			local distance = (hrp.Position - rootPos).Magnitude
			if allowed and distance <= range + cfg.candidateRangeMargin then
				local samples = Vision.getSamples(ctrl, character)
				local visibleCount, tested = 0, 0
				for _, s in ipairs(samples) do
					local toSample = s.position - origin
					local dist = toSample.Magnitude
					local inRange = dist <= range
					local inCone = cosHalf <= -1.5 or (dist > 1e-3 and look:Dot(toSample / dist) >= cosHalf)
					if inRange and inCone then
						tested += 1
						local visible, finalPos, hitInst = castToSample(origin, s.position, ctrl.rayParams, character, cfg)
						if visible then
							visibleCount += 1
						end
						if record then
							table.insert(rays, { from = origin, to = finalPos, visible = visible, blockedBy = if visible then nil else hitInst, sample = s.name })
						end
						if visible and cfg.stopAtFirstVisible then
							break
						end
					end
				end
				table.insert(results, {
					player = player,
					character = character,
					humanoid = humanoid,
					root = hrp,
					distance = distance,
					visible = visibleCount > 0,
					visibleCount = visibleCount,
					sampleCount = tested,
				})
			end
		end
	end
	return results, rays
end

function Vision.radialRay(ctrl, origin: Vector3, direction: Vector3): (Vector3, Instance?)
	local result = Workspace:Raycast(origin, direction, ctrl.rayParams)
	if result then
		return result.Position, result.Instance
	end
	return origin + direction, nil
end

function Vision.capturePose(character: Model, cfg): { any }
	local pose = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and isEligibleBodyPart(d, cfg) then
			table.insert(pose, { name = d.Name, size = d.Size, cframe = d.CFrame })
		end
	end
	return pose
end

return Vision
