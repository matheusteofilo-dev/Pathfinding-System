--!nonstrict

local Rules = require(script.Parent.Rules)

local Validator = {}

local isFinite = Rules.isFinite

local function copyShallow(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

local function checkNumber(errors, path, value, min, max, minExclusive)
	if type(value) ~= "number" or not isFinite(value) then
		table.insert(errors, ("%s must be a finite number (got %s)"):format(path, tostring(value)))
		return false
	end
	if min ~= nil then
		if minExclusive and value <= min then
			table.insert(errors, ("%s must be > %s (got %s)"):format(path, tostring(min), tostring(value)))
			return false
		elseif not minExclusive and value < min then
			table.insert(errors, ("%s must be >= %s (got %s)"):format(path, tostring(min), tostring(value)))
			return false
		end
	end
	if max ~= nil and value > max then
		table.insert(errors, ("%s must be <= %s (got %s)"):format(path, tostring(max), tostring(value)))
		return false
	end
	return true
end

local function checkBool(errors, path, value)
	if type(value) ~= "boolean" then
		table.insert(errors, ("%s must be a boolean (got %s)"):format(path, tostring(value)))
		return false
	end
	return true
end

local function checkOptionalFunction(errors, path, value)
	if value ~= nil and type(value) ~= "function" then
		table.insert(errors, ("%s must be a function or nil (got %s)"):format(path, type(value)))
	end
end

local GLOBAL_NUMBERS = {
	perception = {
		lossGraceTime = { 0, nil, false },
		updateInterval = { 0.01, nil, false },
		maxPerceptionsPerStep = { 1, nil, false },
		onSeeingInterval = { 0, nil, false },
		candidateRangeMargin = { 0, nil, false },
		maxSeeThroughRecasts = { 0, 32, false },
		minVisibleTransparency = { 0, 1, false },
	},
	navigation = {
		repathInterval = { 0.05, nil, false },
		targetMoveThreshold = { 0, nil, false },
		arrivalTolerance = { 0, nil, true },
		preciseArrivalTolerance = { 0, nil, true },
		waypointTolerance = { 0, nil, true },
		stuckTimeout = { 0.1, nil, false },
		minProgressDistance = { 0, nil, false },
		maxRecoveryAttempts = { 0, nil, false },
		recoveryResetDistance = { 0, nil, false },
		moveCommandInterval = { 0.1, nil, false },
		computeTimeout = { 0.5, nil, false },
		maxConcurrentComputes = { 1, nil, false },
		maxAlternatePoints = { 0, nil, false },
		alternateDirections = { 1, nil, false },
		incapacitatedTimeout = { 0, nil, false },
	},
	investigation = {
		searchDuration = { 0, nil, false },
		searchRayCount = { 1, nil, false },
		searchRayRange = { 0, nil, true },
		noiseDedupeWindow = { 0, nil, false },
		noiseDedupeRadius = { 0, nil, false },
		noiseQueueCapacity = { 1, nil, false },
		noiseExpiry = { 0, nil, true },
	},
	gap = {
		probeRange = { 0, nil, true },
		minWidth = { 0, nil, true },
		minMove = { 0, nil, false },
		mergeDistance = { 0, nil, false },
		marchStep = { 0.1, nil, false },
		marchRange = { 1, nil, false },
		entryBackoff = { 0, nil, false },
		cooldown = { 0, nil, false },
		maxGaps = { 1, nil, false },
		sampleStep = { 0.1, nil, false },
		maxApproach = { 0, nil, false },
		reachSlack = { 0, nil, false },
		crossSpeedFactor = { 0.05, 1, false },
		crossLookahead = { 0.1, nil, false },
		bodyDepth = { 0, nil, true },
	},
	pursuit = {
		giveUpTime = { 0.5, nil, false },
		progressDelta = { 0, nil, false },
		ignoreTime = { 0, nil, false },
	},
	movement = {
		doubleTapWindow = { 0.05, nil, false },
		minLandFallTime = { 0, nil, false },
		soundMaxDistance = { 1, nil, false },
	},
	debug = {
		rayLifetime = { 0, nil, false },
		noiseLifetime = { 0, nil, false },
		maxVisualParts = { 0, nil, false },
		labelRefreshInterval = { 0.05, nil, false },
	},
}

function Validator.validateGlobal(config): { string }
	local errors = {}
	if type(config) ~= "table" then
		return { "config must be a table" }
	end
	for section, rules in pairs(GLOBAL_NUMBERS) do
		local sec = config[section]
		if type(sec) ~= "table" then
			table.insert(errors, ("config.%s must be a table"):format(section))
		else
			for key, r in pairs(rules) do
				checkNumber(errors, ("config.%s.%s"):format(section, key), sec[key], r[1], r[2], r[3])
			end
		end
	end
	local inv = config.investigation
	if type(inv) == "table" then
		if inv.noisePriority ~= "InvestigateFirst" and inv.noisePriority ~= "TargetFirst" then
			table.insert(errors, "config.investigation.noisePriority must be 'InvestigateFirst' or 'TargetFirst'")
		end
		if type(inv.searchElevations) ~= "table" or #inv.searchElevations == 0 then
			table.insert(errors, "config.investigation.searchElevations must be a non-empty array of degrees")
		else
			for i, e in ipairs(inv.searchElevations) do
				checkNumber(errors, ("config.investigation.searchElevations[%d]"):format(i), e, -89, 89, false)
			end
		end
	end
	local mv = config.movement
	if type(mv) == "table" then
		for _, group in ipairs({ "speeds", "stepDistance", "noiseRadius" }) do
			if type(mv[group]) ~= "table" then
				table.insert(errors, ("config.movement.%s must be a table"):format(group))
			else
				for k, v in pairs(mv[group]) do
					checkNumber(errors, ("config.movement.%s.%s"):format(group, k), v, 0, nil, group ~= "noiseRadius")
				end
			end
		end
		if type(mv.sounds) ~= "table" then
			table.insert(errors, "config.movement.sounds must be a table")
		else
			for k, snd in pairs(mv.sounds) do
				if type(snd) ~= "table" or type(snd.id) ~= "string" then
					table.insert(errors, ("config.movement.sounds.%s needs a string id"):format(k))
				else
					checkNumber(errors, ("config.movement.sounds.%s.volume"):format(k), snd.volume, 0, nil, false)
					checkNumber(errors, ("config.movement.sounds.%s.speed"):format(k), snd.speed, 0, nil, true)
				end
			end
		end
		checkOptionalFunction(errors, "config.movement.speedResolver", mv.speedResolver)
	end
	local gp = config.gap
	if type(gp) == "table" then
		if type(gp.heights) ~= "table" or #gp.heights == 0 then
			table.insert(errors, "config.gap.heights must be a non-empty array")
		else
			for i, h in ipairs(gp.heights) do
				checkNumber(errors, ("config.gap.heights[%d]"):format(i), h, 0, nil, true)
			end
		end
	end
	if type(config.defaults) ~= "table" then
		table.insert(errors, "config.defaults must be a table")
	end
	if type(config.npcs) ~= "table" then
		table.insert(errors, "config.npcs must be a table")
	end
	if type(config.navigation) == "table" and type(config.navigation.agentDefaults) ~= "table" then
		table.insert(errors, "config.navigation.agentDefaults must be a table")
	end
	return errors
end

function Validator.validateProfile(tag, raw, config)
	local errors = {}
	local p = "config.npcs[\"" .. tostring(tag) .. "\"]"
	if type(raw) ~= "table" then
		return nil, { p .. " must be a table" }
	end
	local defaults = config.defaults
	local out = {}

	local function field(name, min, max, minExclusive)
		local v = raw[name]
		if v == nil then
			v = defaults[name]
		end
		if checkNumber(errors, p .. "." .. name, v, min, max, minExclusive) then
			out[name] = v
		end
	end

	field("speed", 0, nil, true)
	field("hearing", 0, nil, false)
	field("visionRange", 0, nil, true)
	field("fieldOfView", 0, 360, true)

	local ch = raw.chases
	if ch == nil then
		ch = true
	end
	if checkBool(errors, p .. ".chases", ch) then
		out.chases = ch
	end

	local rp = raw.returnPos
	if rp == nil then
		rp = defaults.returnPos
	end
	if checkBool(errors, p .. ".returnPos", rp) then
		out.returnPos = rp
	end

	local agent = copyShallow(config.navigation.agentDefaults)
	if raw.agent ~= nil then
		if type(raw.agent) ~= "table" then
			table.insert(errors, p .. ".agent must be a table")
		else
			for k, v in pairs(raw.agent) do
				agent[k] = v
			end
		end
	end
	checkNumber(errors, p .. ".agent.radius", agent.radius, 0, nil, true)
	checkNumber(errors, p .. ".agent.height", agent.height, 0, nil, true)
	checkBool(errors, p .. ".agent.canJump", agent.canJump)
	checkBool(errors, p .. ".agent.canClimb", agent.canClimb)
	if agent.bodyDepth ~= nil then
		checkNumber(errors, p .. ".agent.bodyDepth", agent.bodyDepth, 0, nil, true)
	end
	out.agent = agent

	if raw.searchRayRange ~= nil then
		if checkNumber(errors, p .. ".searchRayRange", raw.searchRayRange, 0, nil, true) then
			out.searchRayRange = raw.searchRayRange
		end
	end

	checkOptionalFunction(errors, p .. ".onSeeing", raw.onSeeing)
	checkOptionalFunction(errors, p .. ".onStateChanged", raw.onStateChanged)
	checkOptionalFunction(errors, p .. ".canTarget", raw.canTarget)
	out.onSeeing = raw.onSeeing
	out.onStateChanged = raw.onStateChanged
	out.canTarget = raw.canTarget

	if raw.rigMap ~= nil then
		if type(raw.rigMap) ~= "table" then
			table.insert(errors, p .. ".rigMap must be a table { [partName] = { fractionOffset, ... } }")
		else
			out.rigMap = raw.rigMap
		end
	end

	out.tag = tag
	if #errors > 0 then
		return nil, errors
	end
	return out, errors
end

return Validator
