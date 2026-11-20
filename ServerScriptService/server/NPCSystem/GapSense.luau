--!nonstrict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Vision = require(script.Parent.Vision)

local GapSense = {}

local function buildParams(ctrl): RaycastParams
	local list = { ctrl.model }
	if Vision.debugFolder then
		table.insert(list, Vision.debugFolder)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = list
	return rp
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function measure(ctrl, rp: RaycastParams, feet: Vector3, axis: Vector3, rays)
	local cfg = ctrl.config.gap
	local perp = Vector3.new(-axis.Z, 0, axis.X)
	local best = nil
	for _, h in ipairs(cfg.heights) do
		local origin = feet + Vector3.new(0, h, 0)
		local l = Workspace:Raycast(origin, perp * cfg.probeRange, rp)
		local r = Workspace:Raycast(origin, -perp * cfg.probeRange, rp)
		local dl = if l then l.Distance else cfg.probeRange
		local dr = if r then r.Distance else cfg.probeRange
		if rays then
			table.insert(rays, { from = origin, to = if l then l.Position else origin + perp * cfg.probeRange })
			table.insert(rays, { from = origin, to = if r then r.Position else origin - perp * cfg.probeRange })
		end
		local width = dl + dr
		if best == nil or width < best.width then
			best = { width = width, bothHit = l ~= nil and r ~= nil, dl = dl, dr = dr, nl = l and l.Normal, nr = r and r.Normal }
		end
	end
	best.mid = feet + perp * ((best.dl - best.dr) / 2)
	return best
end

local function isNarrow(ctrl, m): boolean
	local diameter = ctrl.profile.agent.radius * 2
	return m.bothHit and m.width < diameter and m.width >= ctrl.config.gap.minWidth
end

local function refineAxis(m, axis: Vector3): Vector3
	if not (m.nl and m.nr) then
		return axis
	end
	local sum = flat(m.nr) - flat(m.nl)
	if sum.Magnitude < 0.2 then
		return axis
	end
	local perp = sum.Unit
	local refined = Vector3.new(perp.Z, 0, -perp.X)
	if refined:Dot(axis) < 0 then
		refined = -refined
	end
	return refined
end

function GapSense.learn(ctrl, feet: Vector3, dir: Vector3, rays)
	local cfg = ctrl.config.gap
	for _, g in ipairs(ctrl.gaps) do
		if (g.center - feet).Magnitude < cfg.mergeDistance then
			return nil
		end
	end
	if #ctrl.gaps >= cfg.maxGaps then
		return nil
	end
	local rp = buildParams(ctrl)
	local m0 = measure(ctrl, rp, feet, dir, rays)
	if not isNarrow(ctrl, m0) then
		return nil
	end

	local axis = refineAxis(m0, dir)
	local m1 = measure(ctrl, rp, feet, axis, rays)
	if not isNarrow(ctrl, m1) then
		axis, m1 = dir, m0
	end
	local center = m1.mid
	local diameter = ctrl.profile.agent.radius * 2

	local function boundary(sign: number): number?
		for s = cfg.marchStep, cfg.marchRange, cfg.marchStep do
			local p = center + axis * (sign * s)
			local m = measure(ctrl, rp, p, axis, rays)
			if not (m.bothHit and m.width < diameter) then
				return s + cfg.entryBackoff
			end
		end
		return nil
	end
	local back, ahead = boundary(-1), boundary(1)
	if not back or not ahead then
		return nil
	end
	return {
		center = center,
		dir = axis,
		entry = center - axis * back,
		exit = center + axis * ahead,
		width = m1.width,
		learnedAt = os.clock(),
	}
end

function GapSense.pick(ctrl, goal: Vector3)
	local pos = ctrl.root.Position
	local maxApproach = ctrl.config.gap.maxApproach
	local bodyDepth = ctrl.profile.agent.bodyDepth or ctrl.config.gap.bodyDepth
	local best, bestCost = nil, math.huge
	for _, g in ipairs(ctrl.gaps) do
		if g.width >= bodyDepth then
			for _, pair in ipairs({ { g.entry, g.exit }, { g.exit, g.entry } }) do
				local from, to = pair[1], pair[2]
				local approach = (from - pos).Magnitude
				local before, after = (goal - from).Magnitude, (goal - to).Magnitude
				if approach <= maxApproach and after < before - 0.5 then
					local cost = approach + after
					if cost < bestCost then
						bestCost = cost
						best = { from = from, center = g.center, to = to, axis = g.dir }
					end
				end
			end
		end
	end
	return best
end

return GapSense
