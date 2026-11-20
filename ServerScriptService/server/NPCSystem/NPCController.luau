--!nonstrict

local Players = game:GetService("Players")

local Rules = require(script.Parent.Rules)
local Vision = require(script.Parent.Vision)
local Navigator = require(script.Parent.Navigator)
local SearchBehavior = require(script.Parent.SearchBehavior)
local GapSense = require(script.Parent.GapSense)

local Controller = {}
Controller.__index = Controller

local nextId = 0
local LOG_LIMIT = 12

function Controller.new(model: Model, tag: string, profile, config, debug, humanoid: Humanoid, root: BasePart)
	nextId += 1
	local seed = config.randomSeed
	local rng = Random.new(if seed then seed + nextId else os.time() * 1000 + nextId)
	local self = setmetatable({
		id = nextId,
		model = model,
		tag = tag,
		profile = profile,
		config = config,
		debug = debug,
		humanoid = humanoid,
		root = root,
		rayParams = Vision.buildParams(model),
		rng = rng,
		state = "Idle",
		stateReason = "registered",
		stateSince = os.clock(),
		home = nil :: Vector3?,
		userMemory = {},
		visual = nil,
		episode = nil,
		episodeCounter = 0,
		pendingLastSeen = false,
		gaps = {},
		track = nil,
		squeeze = nil,
		pursuit = nil,
		suppress = nil,
		lastSqueezeEnd = -math.huge,
		noise = { active = nil, queue = {}, log = {}, stats = { heard = 0, grouped = 0, rejected = 0, expired = 0, ignored = 0 } },
		search = nil,
		searchMode = nil,
		lastScan = nil,
		lastOnSeeingAt = -math.huge,
		callbackBusy = false,
		chaseRetryAt = 0,
		log = {},
		destroyed = false,
		nextPerceiveAt = os.clock() + rng:NextNumber() * config.perception.updateInterval,
		rigWarned = false,
		connections = {},
	}, Controller)
	self.nav = Navigator.new(self)
	return self
end

function Controller:isActive(): boolean
	return not self.destroyed and self.state ~= "Disabled" and self.humanoid.Health > 0 and self.model.Parent ~= nil
end

function Controller:note(msg: string)
	table.insert(self.log, msg)
	if #self.log > LOG_LIMIT then
		table.remove(self.log, 1)
	end
end

local function safeCall(label: string, fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn(("[NPCSystem] %s failed: %s"):format(label, tostring(err)))
	end
	return ok
end

function Controller:_setState(new: string, reason: string)
	local old = self.state
	if old == "Disabled" then
		return
	end
	if old ~= new and not Rules.canTransition(old, new) then
		warn(("[NPCSystem] illegal transition %s -> %s (%s) on %s"):format(old, new, reason, self.model.Name))
		if self.config.stateMachine.strict then
			return
		end
	end
	self.stateReason = reason
	if old == new then
		return
	end
	if self.search and new ~= "Searching" then
		self.search:finish()
		self.search = nil
	end
	self.state = new
	self.squeeze = nil
	self.pursuit = nil
	self.stateSince = os.clock()
	self:note(("%s -> %s (%s)"):format(old, new, reason))
	local cb = self.profile.onStateChanged
	if cb then
		task.spawn(safeCall, "onStateChanged", cb, self.model, old, new, reason)
	end
end

local function noteNoise(self, kind: string, event)
	table.insert(self.noise.log, { kind = kind, position = event.position, radius = event.radius, at = os.clock() })
	if #self.noise.log > LOG_LIMIT then
		table.remove(self.noise.log, 1)
	end
end

function Controller:hear(event)
	if not self:isActive() then
		return
	end
	local inv = self.config.investigation
	local noise = self.noise
	local now = os.clock()
	noise.stats.heard += 1
	if self.state == "Chasing" then
		noise.stats.ignored += 1
		noteNoise(self, "ignored-chase", event)
		return
	end

	local function same(other)
		return (other.position - event.position).Magnitude <= inv.noiseDedupeRadius and now - other.firstAt <= inv.noiseDedupeWindow
	end
	if noise.active and same(noise.active) then
		noise.active.count += 1
		noise.stats.grouped += 1
		noteNoise(self, "grouped", event)
		return
	end
	for _, q in ipairs(noise.queue) do
		if same(q) then
			q.count += 1
			noise.stats.grouped += 1
			noteNoise(self, "grouped", event)
			return
		end
	end

	if #noise.queue >= inv.noiseQueueCapacity then
		noise.stats.rejected += 1
		noteNoise(self, "rejected-capacity", event)
		self:note("noise rejected: queue full")
		return
	end

	event.firstAt = now
	event.count = 1
	table.insert(noise.queue, event)
	noteNoise(self, "queued", event)

	local investigating = self.state == "InvestigatingNoise" or (self.state == "Searching" and self.searchMode == "noise")
	if self.config.investigation.noisePriority == "TargetFirst" then
		if self.state == "Idle" or self.state == "Returning" then
			self:_startNextNoise("noise heard")
		end
	elseif not investigating then
		self:_startNextNoise("noise heard")
	end
end

function Controller:_expireNoises(now: number)
	local q = self.noise.queue
	local expiry = self.config.investigation.noiseExpiry
	for i = #q, 1, -1 do
		if now - q[i].firstAt > expiry then
			self.noise.stats.expired += 1
			noteNoise(self, "expired", q[i])
			table.remove(q, i)
		end
	end
end

function Controller:_startNextNoise(reason: string): boolean
	local noise = self.noise
	if #noise.queue == 0 then
		return false
	end
	local ev = table.remove(noise.queue, 1)
	noise.active = ev
	self.nav:setGoal(ev.position, "noise", true)
	self:_setState("InvestigatingNoise", reason)
	return true
end

function Controller:_observe(result, now: number)
	local old = self.visual
	local root = result.root
	local pos = root.Position
	local sameTarget = old and old.character == result.character

	local velocity, direction = nil, nil
	if sameTarget and old.time and now - old.time <= 1 and now > old.time then
		velocity = (pos - old.position) / (now - old.time)
	elseif sameTarget then
		velocity = old.velocity
	end
	local flatVel = if velocity then Vector3.new(velocity.X, 0, velocity.Z) else nil
	if flatVel and flatVel.Magnitude > 0.5 then
		direction = flatVel.Unit
	elseif sameTarget and old.direction then
		direction = old.direction
	else
		local look = root.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
		if direction.Magnitude > 1e-3 then
			direction = direction.Unit
		end
	end

	if not self.episode or self.episode.lost then
		self.episodeCounter += 1
		self.episode = { id = self.episodeCounter, lost = false }
	end
	self.pendingLastSeen = false

	self.visual = {
		player = result.player,
		character = result.character,
		humanoid = result.humanoid,
		position = pos,
		cframe = root.CFrame,
		direction = direction,
		velocity = velocity,
		time = now,
		pose = Vision.capturePose(result.character, self.config.perception),
		poseVersion = (old and old.poseVersion or 0) + 1,
		visible = true,
	}
end

function Controller:_markLost()
	if self.visual and self.visual.visible then
		self.visual.visible = false
		if self.episode then
			self.episode.lost = true
		end
		self.pendingLastSeen = self.profile.chases
	end
end

function Controller:_validateVisual()
	local v = self.visual
	if not v then
		return
	end
	local player, character = v.player, v.character
	local dead = v.humanoid.Health <= 0
	if dead or not player.Parent or player.Character ~= character or not character.Parent then
		self:note("visual memory discarded (target died/left/changed)")
		self.visual = nil
		self.pendingLastSeen = false
	end
end

function Controller:_fireOnSeeing(target, now: number)
	local cb = self.profile.onSeeing
	if not cb or self.callbackBusy then
		return
	end
	if now - self.lastOnSeeingAt < self.config.perception.onSeeingInterval then
		return
	end
	self.lastOnSeeingAt = now
	self.callbackBusy = true
	local context = {
		npc = self.model,
		distance = target.distance,
		isVisible = true,
		targetHumanoid = target.humanoid,
		lastSeenPosition = self.visual and self.visual.position,
		memory = self.userMemory,
		visiblePoints = target.visibleCount,
		time = now,
	}
	task.spawn(function()
		safeCall("onSeeing", cb, target.player, context)
		self.callbackBusy = false
	end)
end

function Controller:perceive(now: number)
	if not self:isActive() then
		return
	end
	local cfg = self.config
	self:_expireNoises(now)
	self:_validateVisual()

	if self.home == nil and self.humanoid.FloorMaterial ~= Enum.Material.Air then
		self.home = self.root.Position
	end

	local searching = self.state == "Searching"
	local record = self.debug.enabled
	local results, rays = Vision.scan(self, {
		fov = if searching then 360 else self.profile.fieldOfView,
		range = self.profile.visionRange,
		record = record,
	})
	self.lastScan = { results = results, time = now }
	if record and rays then
		self.debug:addVisionRays(self, rays)
	end

	local target = nil
	local current = self.visual and self.visual.player
	local suppress = self.suppress
	if suppress and now >= suppress.untilTime then
		suppress = nil
		self.suppress = nil
	end
	for _, r in ipairs(results) do
		if r.visible and not (suppress and r.character == suppress.character) then
			if r.player == current then
				target = r
				break
			end
			if target == nil or r.distance < target.distance or (r.distance == target.distance and r.player.UserId < target.player.UserId) then
				target = r
			end
		end
	end

	if target then
		self:_observe(target, now)
		self:_fireOnSeeing(target, now)
		self.lostSince = nil
	else

		local v = self.visual
		if v and v.visible then
			if not self.lostSince then
				self.lostSince = now
				if self.state == "Chasing" and self.profile.chases then
					self.nav:setGoal(v.position, "chase (last seen)", true)
				end
			end
			if now - self.lostSince >= cfg.perception.lossGraceTime then
				self.lostSince = nil
				self:_markLost()
			end
		end
	end
	local visible = target ~= nil
	if target and self.profile.chases then
		self:_observeGap(target, now)
	else
		self.track = nil
	end

	local state = self.state
	if state == "Searching" then
		self:_tickSearch(now, visible)
	elseif visible and not self.profile.chases then
	elseif visible then
		if state == "Chasing" then
			if not self.squeeze then
				self.nav:updateGoal(self.visual.position, "chase")
			end
		elseif state == "InvestigatingNoise" then
			if cfg.investigation.noisePriority == "TargetFirst" then
				self:_startChase("target visible (target > noise)")
			end
		else
			self:_startChase("target confirmed")
		end
	else
		if state == "Chasing" and not (self.visual and self.visual.visible) then
			self:_beginGoingToLastSeen("lost sight")
		end
	end

	if self.state == "Chasing" then
		self:_monitorPursuit(now)
	end

	if (self.state == "Idle" or self.state == "Returning") and #self.noise.queue > 0 then
		self:_startNextNoise("pending noise")
	end
end

function Controller:_startChase(reason: string)
	table.clear(self.noise.queue)
	self.noise.active = nil
	self:_setState("Chasing", reason)
	self.nav:setGoal(self.visual.position, "chase")
end

function Controller:_beginGoingToLastSeen(reason: string)
	if not self.visual then
		self:_finishInvestigation("no memory")
		return
	end
	self:_setState("GoingToLastSeen", reason)
	self.nav:setGoal(self.visual.position, "last seen", true)
end

function Controller:_beginSearch(mode: string)
	self.nav:stop()
	self.searchMode = mode
	self:_setState("Searching", "arrived (" .. mode .. ")")
	self.search = SearchBehavior.new(self, mode, os.clock())
end

function Controller:_tickSearch(now: number, visible: boolean)
	if not self.search then
		self:_finishInvestigation("search missing")
		return
	end
	if visible then
		if self.searchMode == "noise" and self.config.investigation.noisePriority == "InvestigateFirst" and #self.noise.queue > 0 then
			self.search:finish()
			self.search = nil
			self.noise.active = nil
			self:_startNextNoise("noise spot checked; next noise")
			return
		end

		self.search:finish()
		self.search = nil
		self.noise.active = nil
		self:_startChase("found during search")
		return
	end
	local done, rays = self.search:tick(now, self.debug.enabled)
	if rays then
		self.debug:addSearchRays(self, rays)
	end
	if done then
		self:_onSearchDone()
	end
end

function Controller:_onSearchDone()
	local mode = self.searchMode
	self.search:finish()
	self.search = nil
	if mode == "noise" then
		self.noise.active = nil
	end

	if mode == "lastSeen" then
		self.pendingLastSeen = false
	end
	self:_finishInvestigation("search finished")
end

function Controller:_finishInvestigation(reason: string)
	local targetFirst = self.config.investigation.noisePriority == "TargetFirst"
	if not targetFirst and self:_startNextNoise(reason .. "; next noise") then
		return
	end
	if self.visual and self.visual.visible and self.profile.chases then
		self:_startChase(reason .. "; target visible")
		return
	end
	if self.pendingLastSeen and self.visual then
		self:_beginGoingToLastSeen(reason .. "; resume last seen")
		return
	end
	if targetFirst and self:_startNextNoise(reason .. "; next noise") then
		return
	end
	if self.profile.returnPos and self.home then
		self:_setState("Returning", reason .. "; returnPos")
		self.nav:setGoal(self.home, "return")
		return
	end
	self.nav:stop()
	self:_setState("Idle", reason)
end

local function ctrl_flat(a: Vector3, b: Vector3): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

function Controller:_observeGap(target, now: number)
	local root, hum = target.root, target.humanoid
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + hum.HipHeight, 0)
	local tr = self.track
	if tr and tr.character == target.character and now - tr.time <= 0.6 then
		local delta = Vector3.new(feet.X - tr.feet.X, 0, feet.Z - tr.feet.Z)
		local length = delta.Magnitude
		if length >= self.config.gap.minMove then
			local dir = delta.Unit
			local rays = if self.debug.enabled then {} else nil
			local samples = math.clamp(math.ceil(length / self.config.gap.sampleStep), 1, 12)
			for i = 1, samples do
				local p = tr.feet:Lerp(feet, i / samples)
				local gap = GapSense.learn(self, p, dir, rays)
				if gap then
					table.insert(self.gaps, gap)
					self:note(("gap learned (width %.1f)"):format(gap.width))
					break
				end
			end
			if rays and #rays > 0 then
				self.debug:addGapRays(self, rays)
			end
		end
	end
	self.track = { character = target.character, feet = feet, time = now }
end

function Controller:_monitorPursuit(now: number)
	local cfg = self.config.pursuit
	local nav = self.nav
	local p = self.pursuit
	if not p then
		p = { lastImproveAt = now, ref = nil }
		self.pursuit = p
	end
	if self.squeeze then
		p.lastImproveAt = now
		return
	end
	local metric = nil
	if nav.status == "Arrived" and not nav.usedAlternate then
		metric = 0
	elseif nav.status == "Moving" and not nav.usedAlternate and not nav.routeMode then
		metric = nav:remainingPathLength()
	end
	if metric ~= nil then
		if p.ref == nil or metric < p.ref - cfg.progressDelta or metric <= self.config.navigation.arrivalTolerance * 2 then
			p.ref = metric
			p.lastImproveAt = now
		end
	elseif nav.status == "Computing" then
		return
	end
	if now - p.lastImproveAt >= cfg.giveUpTime then
		self:_abandonPursuit(now)
	end
end

function Controller:_abandonPursuit(now: number)
	local v = self.visual
	if v then
		self.suppress = { character = v.character, untilTime = now + self.config.pursuit.ignoreTime }
	end
	self:note("pursuit abandoned: cannot reach or shorten the path to the target")
	self.visual = nil
	self.pendingLastSeen = false
	self.pursuit = nil
	self.squeeze = nil
	self:_finishInvestigation("pursuit abandoned")
end

function Controller:_tryGap(goal: Vector3): boolean
	if os.clock() - self.lastSqueezeEnd < self.config.gap.cooldown then
		return false
	end
	local pick = GapSense.pick(self, goal)
	if not pick then
		self:note("no learned gap fits the body and helps reach the goal")
		return false
	end
	self.squeeze = { from = pick.from, center = pick.center, to = pick.to, goal = goal, stage = "approach" }
	self:note("gap detour: approaching entry")
	self.nav:setGoal(pick.from, "gap approach", true)
	return true
end

function Controller:_squeezeStep(status: string): boolean
	local sq = self.squeeze
	if sq.stage == "approach" and status == "Arrived" then
		sq.stage = "crossing"
		local dir = Vector3.new(sq.to.X - sq.from.X, 0, sq.to.Z - sq.from.Z).Unit
		local facing = Vector3.new(-dir.Z, 0, dir.X)
		self:note("gap detour: crossing sideways")
		self.nav:setRoute({ sq.to }, "squeeze (sideways)", facing, sq.from)
		return true
	elseif sq.stage == "crossing" and status == "Arrived" then
		sq.stage = "resume"
		self.nav:setGoal(sq.goal, "after squeeze", true)
		return true
	end
	self.squeeze = nil
	self.lastSqueezeEnd = os.clock()
	return false
end

function Controller:_onNavDone(status: string, failReason: string?)
	local state = self.state
	if self.squeeze and self:_squeezeStep(status) then
		return
	end

	if state ~= "Searching" and not self.squeeze and #self.gaps > 0 then
		local nav = self.nav
		local goal = nav.requested
		local unreachable = status == "Failed" and (failReason == "no-path" or failReason == "stuck" or failReason == "path-end-mismatch")
		if status == "Arrived" and nav.usedAlternate and goal then
			local d = ctrl_flat(self.root.Position, goal)
			unreachable = d > self.config.gap.reachSlack
		end
		if unreachable and goal and self:_tryGap(goal) then
			return
		end
	end
	if state == "Chasing" then
		if status == "Failed" then
			self:note("chase path failed: " .. tostring(failReason))
		end
	elseif state == "InvestigatingNoise" then
		if status == "Arrived" then
			self:_beginSearch("noise")
		else
			self:note("noise unreachable: " .. tostring(failReason))
			self.noise.active = nil
			self:_finishInvestigation("noise unreachable")
		end
	elseif state == "GoingToLastSeen" then
		if status == "Failed" then
			self:note("last seen unreachable: " .. tostring(failReason))
		end
		self:_beginSearch("lastSeen")
	elseif state == "Returning" then
		self.nav:stop()
		self:_setState("Idle", if status == "Arrived" then "returned home" else "return failed: " .. tostring(failReason))
	end
end

function Controller:update(now: number)
	if not self:isActive() then
		return
	end
	self.nav:step(now)
	local nav = self.nav
	if (nav.status == "Arrived" or nav.status == "Failed") and not nav.consumed then
		nav.consumed = true
		self:_onNavDone(nav.status, nav.failReason)
	end
	if self.state == "Chasing" and nav.status == "Failed" and now >= self.chaseRetryAt and self.visual and not self.squeeze then
		self.chaseRetryAt = now + 1
		nav:setGoal(self.visual.position, "chase (retry)")
	end
end

function Controller:destroy(reason: string)
	if self.destroyed then
		return
	end
	self:_setState("Disabled", reason)
	self.destroyed = true
	if self.search then
		self.search:finish()
		self.search = nil
	end
	self.nav:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	self.debug:removeController(self)
	self.visual = nil
	table.clear(self.noise.queue)
	self.noise.active = nil
end

return Controller
