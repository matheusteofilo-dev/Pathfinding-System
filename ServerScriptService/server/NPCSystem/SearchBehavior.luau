--!nonstrict

local Vision = require(script.Parent.Vision)

local SearchBehavior = {}
SearchBehavior.__index = SearchBehavior

function SearchBehavior.new(ctrl, mode: string, now: number)
	local inv = ctrl.config.investigation
	local _, yaw = ctrl.root.CFrame:ToOrientation()
	ctrl.humanoid.AutoRotate = false
	return setmetatable({
		ctrl = ctrl,
		mode = mode,
		startedAt = now,
		duration = inv.searchDuration,
		elevations = inv.searchElevations,
		count = inv.searchRayCount,
		total = inv.searchRayCount * #inv.searchElevations,
		fired = 0,
		startYaw = yaw,
		range = math.min(ctrl.profile.visionRange, ctrl.profile.searchRayRange or inv.searchRayRange),
	}, SearchBehavior)
end

function SearchBehavior:tick(now: number, record: boolean)
	local ctrl = self.ctrl
	local elapsed = now - self.startedAt
	local frac = if self.duration > 0 then math.min(1, elapsed / self.duration) else 1
	local due = math.floor(frac * self.total + 0.5)
	local origin = Vision.getEye(ctrl)
	local rays = if record then {} else nil
	local lastYaw = nil
	local E = #self.elevations

	while self.fired < due do
		local i = self.fired
		local angleIdx = i // E
		local elevIdx = i % E
		local yaw = self.startYaw + angleIdx * (2 * math.pi / self.count)
		local pitch = math.rad(self.elevations[elevIdx + 1])
		local dir = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector * self.range
		local finalPos, inst = Vision.radialRay(ctrl, origin, dir)
		if record then
			table.insert(rays, { from = origin, to = finalPos, blockedBy = inst })
		end
		lastYaw = yaw
		self.fired += 1
	end

	if lastYaw then
		local pos = ctrl.root.Position
		ctrl.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, lastYaw, 0)
	end

	return elapsed >= self.duration, rays
end

function SearchBehavior:finish()
	if self.ctrl.humanoid.Parent then
		self.ctrl.humanoid.AutoRotate = true
	end
end

return SearchBehavior
