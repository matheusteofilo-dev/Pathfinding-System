--!nonstrict

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Vision = require(script.Parent.Vision)

local Navigator = {}
Navigator.__index = Navigator

local activeComputes = 0

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Navigator.new(ctrl)
	return setmetatable({
		ctrl = ctrl,
		cfg = ctrl.config.navigation,
		ctrlConfig = ctrl.config,
		humanoid = ctrl.humanoid,
		root = ctrl.root,
		status = "Idle",
		failReason = nil,
		failedAt = -math.huge,
		routeMode = false,
		sidewaysFacing = nil,
		crossLine = nil,
		arrivalTol = ctrl.config.navigation.arrivalTolerance,
		consumed = true,
		requested = nil,
		destination = nil,
		usedAlternate = false,
		goalReason = nil,
		waypoints = nil,
		wpIndex = 1,
		pathVersion = 0,
		computeGen = 0,
		inflight = 0,
		pendingRepath = nil,
		lastRepathAt = -math.huge,
		lastRepathReason = nil,
		goalStartedAt = 0,
		attempts = 0,
		lastRecoveryNote = nil,
		blockedCount = 0,
		blockedConn = nil,
		sidestepUntil = 0,
		sidestepPoint = nil,
		sideSign = 1,
		useAlternate = false,
		lastMoveCmdAt = -math.huge,
		cmdIndex = 0,
		jumpedIndex = 0,
		bestDist = math.huge,
		lastProgressAt = os.clock(),
		lastPos = ctrl.root.Position,
		distSinceRecovery = 0,
		incapSince = nil,
		destroyed = false,
	}, Navigator)
end

function Navigator:_agentParams()
	local a = self.ctrl.profile.agent
	return {
		AgentRadius = a.radius,
		AgentHeight = a.height,
		AgentCanJump = a.canJump,
		AgentCanClimb = a.canClimb,
		Costs = a.costs,
	}
end

function Navigator:_disconnectBlocked()
	if self.blockedConn then
		self.blockedConn:Disconnect()
		self.blockedConn = nil
	end
end

function Navigator:remainingPathLength(): number?
	local wps = self.waypoints
	if not wps or self.routeMode or self.wpIndex > #wps then
		return nil
	end
	local total = (wps[self.wpIndex].Position - self.root.Position).Magnitude
	for i = self.wpIndex, #wps - 1 do
		total += (wps[i + 1].Position - wps[i].Position).Magnitude
	end
	return total
end

function Navigator:_endSideways()
	if self.sidewaysFacing then
		self.sidewaysFacing = nil
		self.crossLine = nil
		if self.humanoid.Parent then
			self.humanoid.AutoRotate = true
			self.humanoid.WalkSpeed = self.ctrl.profile.speed
		end
	end
end

function Navigator:_stopMoving()
	local hum = self.humanoid
	if hum.Parent and hum.Health > 0 then
		hum:MoveTo(self.root.Position)
	end
end

function Navigator:_snapGround(position: Vector3): (Vector3, boolean)
	local list = { self.ctrl.model }
	if Vision.debugFolder then
		table.insert(list, Vision.debugFolder)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	local result = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -self.cfg.groundSnapDepth, 0), params)
	if result then
		return result.Position, true
	end
	return position, false
end

function Navigator:_stale(gen: number): boolean
	return self.destroyed or gen ~= self.computeGen
end

function Navigator:setGoal(position: Vector3, reason: string, precise: boolean?)
	local now = os.clock()
	self:_endSideways()
	self.routeMode = false
	self.arrivalTol = if precise then self.cfg.preciseArrivalTolerance else self.cfg.arrivalTolerance
	self:_disconnectBlocked()
	self.computeGen += 1
	self.waypoints = nil
	self.requested = position
	self.destination = nil
	self.usedAlternate = false
	self.goalReason = reason
	self.attempts = 0
	self.useAlternate = false
	self.failReason = nil
	self.consumed = false
	self.pendingRepath = nil
	self.sidestepUntil = 0
	self.goalStartedAt = now
	self.distSinceRecovery = 0
	self.lastPos = self.root.Position

	local pos = self.root.Position
	if flatDistance(pos, position) <= self.arrivalTol and math.abs(pos.Y - position.Y) <= self.cfg.verticalTolerance + 3 then
		self.destination = position
		self:_arrive()
		return
	end
	self.status = "Computing"
	self:_requestPath("new goal", true)
end

function Navigator:setRoute(points: { Vector3 }, reason: string, facing: Vector3?, lineOrigin: Vector3?)
	local now = os.clock()
	self:_endSideways()
	if facing then
		self.sidewaysFacing = facing
		self.humanoid.AutoRotate = false
		self.humanoid.WalkSpeed = self.ctrl.profile.speed * self.ctrlConfig.gap.crossSpeedFactor
		local origin = lineOrigin or points[1]
		local last = points[#points]
		local delta = Vector3.new(last.X - origin.X, 0, last.Z - origin.Z)
		if delta.Magnitude > 0.01 then
			self.crossLine = { origin = origin, axis = delta.Unit, length = delta.Magnitude }
		end
	end
	self:_disconnectBlocked()
	self.computeGen += 1
	self.routeMode = true
	self.arrivalTol = self.cfg.preciseArrivalTolerance
	self.requested = points[#points]
	self.destination = points[#points]
	self.usedAlternate = false
	self.goalReason = reason
	self.attempts = 0
	self.useAlternate = false
	self.failReason = nil
	self.consumed = false
	self.pendingRepath = nil
	self.sidestepUntil = 0
	self.goalStartedAt = now
	self.distSinceRecovery = 0
	self.lastPos = self.root.Position
	local wps = {}
	for i, p in ipairs(points) do
		local prev = points[i - 1]
		local jump = prev ~= nil and p.Y - prev.Y > 2.5
		wps[i] = { Position = p, Action = if jump then Enum.PathWaypointAction.Jump else Enum.PathWaypointAction.Walk }
	end
	self.waypoints = wps
	self.wpIndex = 1
	self.pathVersion += 1
	self.status = "Moving"
	self.bestDist = math.huge
	self.lastProgressAt = now
	self.lastMoveCmdAt = -math.huge
	self.cmdIndex = 0
end

function Navigator:updateGoal(position: Vector3, reason: string)
	local now = os.clock()
	local status = self.status
	if self.requested and status ~= "Idle" then
		if (position - self.requested).Magnitude < self.cfg.targetMoveThreshold then
			if status ~= "Failed" or now - self.failedAt < 1 then
				return
			end
		end
	end
	if now - self.lastRepathAt < self.cfg.repathInterval then
		return
	end
	if status == "Moving" or status == "Computing" then
		self.requested = position
		self:_requestPath("target moved", false)
	else
		self:setGoal(position, reason)
	end
end

function Navigator:stop()
	self:_endSideways()
	self:_disconnectBlocked()
	self.computeGen += 1
	self.waypoints = nil
	self.requested = nil
	self.destination = nil
	self.pendingRepath = nil
	self.status = "Idle"
	self.consumed = true
	self.sidestepUntil = 0
	self:_stopMoving()
end

function Navigator:destroy()
	self:_endSideways()
	self.destroyed = true
	self:_disconnectBlocked()
	self.computeGen += 1
	self.waypoints = nil
end

function Navigator:_arrive()
	self:_endSideways()
	self.status = "Arrived"
	self.consumed = false
	self.waypoints = nil
	self:_disconnectBlocked()
	self:_stopMoving()
end

function Navigator:_fail(reason: string)
	self:_endSideways()
	self.status = "Failed"
	self.failReason = reason
	self.failedAt = os.clock()
	self.consumed = false
	self.waypoints = nil
	self.computeGen += 1
	self:_disconnectBlocked()
	self:_stopMoving()
end

function Navigator:_requestPath(why: string, force: boolean)
	if self.destroyed or self.requested == nil or self.routeMode then
		return
	end
	local now = os.clock()
	local minGap = if force then 0.15 else self.cfg.repathInterval
	if now - self.lastRepathAt < minGap or activeComputes >= self.cfg.maxConcurrentComputes or self.inflight >= 2 then
		self.pendingRepath = why
		return
	end
	self.pendingRepath = nil
	self.lastRepathAt = now
	self.lastRepathReason = why
	self.computeGen += 1
	local gen = self.computeGen
	local target = self.requested
	local useAlt = self.useAlternate
	self.inflight += 1
	activeComputes += 1
	task.spawn(function()
		local ok, err = pcall(self._compute, self, gen, target, useAlt)
		self.inflight -= 1
		activeComputes -= 1
		if not ok then
			warn(("[NPCSystem] path compute error for %s: %s"):format(self.ctrl.model.Name, tostring(err)))
			if not self:_stale(gen) then
				self:_fail("compute-error")
			end
		end
	end)
end

function Navigator:_newPath(from: Vector3, to: Vector3)
	local path = PathfindingService:CreatePath(self:_agentParams())
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		return path
	end
	return nil
end

function Navigator:_findAlternate(origin: Vector3, dest: Vector3, gen: number)
	local cfg = self.cfg
	local candidates = {}
	for _, radius in ipairs(cfg.alternateRadii) do
		for i = 0, cfg.alternateDirections - 1 do
			local a = (i / cfg.alternateDirections) * 2 * math.pi
			local p = dest + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			table.insert(candidates, { point = p, radius = radius, toOrigin = (p - origin).Magnitude })
		end
	end
	table.sort(candidates, function(x, y)
		if x.radius ~= y.radius then
			return x.radius < y.radius
		end
		return x.toOrigin < y.toOrigin
	end)
	local tried = 0
	for _, c in ipairs(candidates) do
		if tried >= cfg.maxAlternatePoints then
			break
		end
		local ground, hit = self:_snapGround(c.point)
		if hit then
			tried += 1
			local path = self:_newPath(origin, ground)
			if self:_stale(gen) then
				return nil
			end
			if path then
				return { path = path, dest = ground }
			end
		end
	end
	return nil
end

function Navigator:_compute(gen: number, target: Vector3, useAlt: boolean)
	local origin = self.root.Position
	local dest = self:_snapGround(target)
	if not useAlt then
		local path = self:_newPath(origin, dest)
		if self:_stale(gen) then
			return
		end
		if path then
			self:_applyPath(path, dest, false)
			return
		end
	end
	local alt = self:_findAlternate(origin, dest, gen)
	if self:_stale(gen) then
		return
	end
	if alt then
		self:_applyPath(alt.path, alt.dest, true)
	elseif self.waypoints == nil then
		self:_fail("no-path")
	else
		self.lastRepathReason = (self.lastRepathReason or "") .. " (no path; keeping current)"
	end
end

function Navigator:_applyPath(path: Path, dest: Vector3, isAlt: boolean)
	local wps = path:GetWaypoints()
	if #wps == 0 then
		if self.waypoints == nil then
			self:_fail("empty-path")
		end
		return
	end
	self:_disconnectBlocked()
	self.waypoints = wps
	self.wpIndex = if #wps >= 2 then 2 else 1
	self.pathVersion += 1
	self.destination = dest
	self.usedAlternate = isAlt
	self.status = "Moving"
	self.bestDist = math.huge
	self.lastProgressAt = os.clock()
	self.lastMoveCmdAt = -math.huge
	self.cmdIndex = 0
	self.blockedConn = path.Blocked:Connect(function(blockedIdx: number)
		if not self.destroyed and self.waypoints == wps and blockedIdx >= self.wpIndex then
			self.blockedCount += 1
			self:_requestPath("blocked at waypoint " .. blockedIdx, true)
		end
	end)
end

local function isIncapacitated(hum: Humanoid): boolean
	if hum.Sit or hum.PlatformStand then
		return true
	end
	local s = hum:GetState()
	return s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown or s == Enum.HumanoidStateType.Physics
end

function Navigator:step(now: number)
	if self.destroyed then
		return
	end
	local status = self.status
	if status ~= "Moving" and status ~= "Computing" then
		return
	end
	local hum, cfg = self.humanoid, self.cfg
	if hum.Health <= 0 then
		self:_fail("agent-dead")
		return
	end

	if isIncapacitated(hum) then
		self.incapSince = self.incapSince or now
		self.lastProgressAt = now
		if now - self.incapSince > cfg.incapacitatedTimeout then
			self:_fail("incapacitated")
		end
		return
	end
	self.incapSince = nil

	if self.pendingRepath then
		self:_requestPath(self.pendingRepath, false)
	end

	if status == "Computing" then
		if now - self.goalStartedAt > cfg.computeTimeout and self.inflight == 0 then
			self:_fail("compute-timeout")
		elseif now - self.goalStartedAt > cfg.computeTimeout * 2 then
			self:_fail("compute-timeout")
		end
		return
	end

	local pos = self.root.Position
	if self.sidewaysFacing then
		self.root.CFrame = CFrame.lookAt(pos, pos + self.sidewaysFacing)
		self.root.AssemblyAngularVelocity = Vector3.zero
	end

	self.distSinceRecovery += flatDistance(pos, self.lastPos)
	self.lastPos = pos
	if self.attempts > 0 and self.distSinceRecovery >= cfg.recoveryResetDistance then
		self.attempts = 0
		self.distSinceRecovery = 0
	end

	if now < self.sidestepUntil then
		hum:MoveTo(self.sidestepPoint)
		return
	elseif self.sidestepUntil > 0 then
		self.sidestepUntil = 0
		self.lastProgressAt = now
		self:_requestPath("after sidestep", true)
	end

	local wps = self.waypoints
	if wps == nil then
		return
	end

	local feetY = pos.Y - (hum.HipHeight + self.root.Size.Y * 0.5)
	while self.wpIndex <= #wps do
		local wp = wps[self.wpIndex]
		local tol = if self.wpIndex == #wps then self.arrivalTol else cfg.waypointTolerance
		if flatDistance(pos, wp.Position) <= tol and math.abs(feetY - wp.Position.Y) <= cfg.verticalTolerance then
			self.wpIndex += 1
			self.bestDist = math.huge
			self.lastProgressAt = now
		else
			break
		end
	end

	if self.wpIndex > #wps then
		self:_onPathEnd(now)
		return
	end

	local wp = wps[self.wpIndex]
	local flat = flatDistance(pos, wp.Position)

	if wp.Action == Enum.PathWaypointAction.Jump and self.ctrl.profile.agent.canJump and flat <= cfg.jumpTriggerDistance and self.jumpedIndex ~= self.wpIndex then
		self.jumpedIndex = self.wpIndex
		hum.Jump = true
	end

	local line = self.crossLine
	if line then
		local rel = Vector3.new(pos.X - line.origin.X, 0, pos.Z - line.origin.Z)
		local t = math.clamp(rel:Dot(line.axis) + self.ctrlConfig.gap.crossLookahead, 0, line.length)
		local aim = line.origin + line.axis * t
		hum:MoveTo(Vector3.new(aim.X, wp.Position.Y, aim.Z))
		self.cmdIndex = self.wpIndex
		self.lastMoveCmdAt = now
	elseif self.cmdIndex ~= self.wpIndex or now - self.lastMoveCmdAt >= cfg.moveCommandInterval then
		hum:MoveTo(wp.Position)
		self.cmdIndex = self.wpIndex
		self.lastMoveCmdAt = now
	end

	if flat < self.bestDist - cfg.minProgressDistance then
		self.bestDist = flat
		self.lastProgressAt = now
	elseif now - self.lastProgressAt >= cfg.stuckTimeout then
		if self.wpIndex == #wps and flat <= self.arrivalTol + 1 then
			self:_arrive()
			return
		end
		self:_onStuck(now, flat)
	end
end

function Navigator:_onPathEnd(now: number)
	local pos = self.root.Position
	local dest = self.destination or self.requested
	if self.routeMode then
		self:_arrive()
		return
	end
	if flatDistance(pos, dest) <= self.arrivalTol + 0.5 then
		self:_arrive()
		return
	end

	if self.inflight > 0 or self.pendingRepath then
		return
	end
	self.attempts += 1
	self.lastRecoveryNote = ("path ended %.1f studs from destination"):format(flatDistance(pos, dest))
	if self.attempts > self.cfg.maxRecoveryAttempts then
		self:_fail("path-end-mismatch")
	else
		self:_requestPath("path ended short", true)
	end
end

function Navigator:_onStuck(now: number, distanceToWaypoint: number)
	local cfg = self.cfg
	self.attempts += 1
	self.distSinceRecovery = 0
	self.lastProgressAt = now
	self.bestDist = math.huge
	if self.sidewaysFacing then
		self.lastRecoveryNote = "stuck while crossing sideways"
		self:_fail("stuck")
		return
	end
	self.lastRecoveryNote = ("stuck #%d: no progress to waypoint %d (%.1f studs left)"):format(self.attempts, self.wpIndex, distanceToWaypoint)

	if self.attempts > cfg.maxRecoveryAttempts or (self.routeMode and self.attempts >= 3) then
		self:_fail("stuck")
		return
	end

	local a = self.attempts
	if a == 1 then
		if self.ctrl.profile.agent.canJump then
			self.humanoid.Jump = true
		end
		self:_requestPath("stuck: jump + repath", true)
	elseif a == 2 then
		self.sideSign = -self.sideSign
		self.sidestepPoint = self.root.Position + self.root.CFrame.RightVector * (cfg.sidestepDistance * self.sideSign)
		self.sidestepUntil = now + cfg.sidestepDuration
	else
		self.useAlternate = true
		self:_requestPath("stuck: alternate reachable point", true)
	end
end

return Navigator
