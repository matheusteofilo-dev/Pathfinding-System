--!nonstrict

local config = {
	randomSeed = 1 :: number?,

	debug = {
		enabled = true,
		showVisionRays = true,
		showLastSeenGhost = true,
		showPaths = true,
		showNoise = true,
		showSearchRays = true,
		showState = true,
		showHearingRange = false,
		showGaps = true,
		panelUserIds = {},
		rayLifetime = 0.15,
		noiseLifetime = 3,
		noiseStyle = {
			default = { color = Color3.fromRGB(0, 230, 255), lifetime = 3 },
			walk = { color = Color3.fromRGB(0, 230, 255), lifetime = 0.8 },
			sprint = { color = Color3.fromRGB(255, 60, 150), lifetime = 0.8 },
			sneak = { color = Color3.fromRGB(120, 255, 160), lifetime = 0.8 },
			jump = { color = Color3.fromRGB(190, 255, 60), lifetime = 1.2 },
			land = { color = Color3.fromRGB(255, 255, 120), lifetime = 1.2 },
		},
		maxVisualParts = 900,
		labelRefreshInterval = 0.25,
	},

	perception = {
		lossGraceTime = 1,
		updateInterval = 0.10,
		maxPerceptionsPerStep = 6,
		onSeeingInterval = 0.10,
		candidateRangeMargin = 8,
		stopAtFirstVisible = false,
		maxSeeThroughRecasts = 6,
		seeThroughAttribute = "NPCSeeThrough",
		minVisibleTransparency = 0.95,
		ignoredBodyParts = { HumanoidRootPart = true },
		eyeAttachmentName = "VisionOrigin",
		eyeFallbackOffset = Vector3.new(0, 1.5, 0),
		rigs = {
			R15 = {
				Head = { Vector3.new(0, 0, 0), Vector3.new(0, 0.3, 0) },
				UpperTorso = { Vector3.new(0, 0.25, 0), Vector3.new(0, -0.25, 0) },
				LowerTorso = { Vector3.new(0, 0, 0) },
				LeftUpperArm = { Vector3.new(0, 0, 0) },
				RightUpperArm = { Vector3.new(0, 0, 0) },
				LeftUpperLeg = { Vector3.new(0, 0, 0) },
				RightUpperLeg = { Vector3.new(0, 0, 0) },
				LeftFoot = { Vector3.new(0, -0.2, 0) },
				RightFoot = { Vector3.new(0, -0.2, 0) },
			},
			R6 = {
				Head = { Vector3.new(0, 0, 0), Vector3.new(0, 0.3, 0) },
				Torso = { Vector3.new(0, 0.3, 0), Vector3.new(0, -0.3, 0) },
				["Left Arm"] = { Vector3.new(0, 0, 0) },
				["Right Arm"] = { Vector3.new(0, 0, 0) },
				["Left Leg"] = { Vector3.new(0, 0, 0), Vector3.new(0, -0.4, 0) },
				["Right Leg"] = { Vector3.new(0, 0, 0), Vector3.new(0, -0.4, 0) },
			},
		},
	},

	navigation = {
		repathInterval = 0.35,
		targetMoveThreshold = 3,
		arrivalTolerance = 2,
		preciseArrivalTolerance = 0.8,
		waypointTolerance = 2.5,
		stuckTimeout = 1.5,
		minProgressDistance = 0.5,
		maxRecoveryAttempts = 3,
		recoveryResetDistance = 10,
		sidestepDistance = 3,
		sidestepDuration = 0.45,
		moveCommandInterval = 1.0,
		jumpTriggerDistance = 4,
		computeTimeout = 6,
		maxConcurrentComputes = 6,
		incapacitatedTimeout = 6,
		maxAlternatePoints = 6,
		alternateRadii = { 4, 8, 14 },
		alternateDirections = 8,
		groundSnapDepth = 120,
		verticalTolerance = 6,
		agentDefaults = { radius = 2, height = 5, canJump = true, canClimb = false },
	},

	investigation = {
		noisePriority = "TargetFirst",
		searchDuration = 3,
		searchRayCount = 24,
		searchElevations = { -15, 0, 25 },
		searchRayRange = 60,
		noiseDedupeWindow = 0.75,
		noiseDedupeRadius = 2,
		noiseQueueCapacity = 16,
		noiseExpiry = 30,
	},

	gap = {
		heights = { 1, 2.5, 4 },
		probeRange = 6,
		minWidth = 1.0,
		minMove = 0.25,
		mergeDistance = 3,
		marchStep = 1,
		marchRange = 12,
		entryBackoff = 1.5,
		cooldown = 6,
		maxGaps = 16,
		sampleStep = 0.5,
		maxApproach = 40,
		bodyDepth = 1.0,
		crossSpeedFactor = 0.5,
		crossLookahead = 1.5,
		reachSlack = 2.5,
	},

	pursuit = {
		giveUpTime = 10,
		progressDelta = 2,
		ignoreTime = 20,
	},

	movement = {
		enabled = true,
		doubleTapWindow = 0.3,
		speeds = { walk = 16, sprint = 26, sneak = 16 },
		stepDistance = { walk = 4, sprint = 5.5, sneak = 3 },
		noiseRadius = { walk = 18, sprint = 36, sneak = 6, jump = 24, land = 28 },
		minLandFallTime = 0.3,
		soundMaxDistance = 80,
		sounds = {
			walk = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.5, speed = 1 },
			sprint = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.8, speed = 1.35 },
			sneak = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.15, speed = 0.8 },
			jump = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.7, speed = 1 },
			land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = 1 },
		},
		speedResolver = nil :: ((Player, string, number) -> number?)?,
	},

	stateMachine = {
		strict = false,
	},

	managedArea = nil :: { center: Vector3, size: Vector3 }?,

	testScene = { enabled = true },

	defaults = {
		speed = 16,
		hearing = 40,
		returnPos = true,
		visionRange = 80,
		fieldOfView = 180,
	},

	npcs = {
		["citizen"] = {
			chases = false,
			speed = 10,
			hearing = 0,
			returnPos = false,
			visionRange = 70,
			fieldOfView = 180,
			onSeeing = function(plr: Player, context: any)
				context.npc:SetAttribute("SeeingPlayer", plr.Name)
			end,
		},

		["bandit"] = {
			speed = 16,
			hearing = 40,
			returnPos = true,

			visionRange = 80,
			fieldOfView = 180,

			agent = {
				radius = 2,
				height = 5,
				canJump = true,
				canClimb = false,
			},

			onSeeing = function(plr: Player, context: any)
				if context.distance > 3 then
					return
				end

				local targetHumanoid = context.targetHumanoid
				if not targetHumanoid or targetHumanoid.Health <= 0 then
					return
				end

				local now = os.clock()
				local lastPowerAt = context.memory.lastPowerAt or -math.huge
				if now - lastPowerAt < 1 then
					return
				end

				context.memory.lastPowerAt = now
				targetHumanoid:TakeDamage(10)
			end,
		},
	},
}

return config
