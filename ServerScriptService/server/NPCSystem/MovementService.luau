--!nonstrict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementService = {}

function MovementService.start(config, emitNoise: (Vector3, number, string) -> ())
	local cfg = config.movement
	if not cfg.enabled then
		return function() end
	end

	local remote = ReplicatedStorage:FindFirstChild("MovementInputRemote")
	if not remote then
		warn("[NPCSystem] MovementInputRemote not found in ReplicatedStorage; player movement noise is disabled.")
		return function() end
	end
	remote:SetAttribute("DoubleTapWindow", cfg.doubleTapWindow)

	local states = {}
	local connections = {}

	local function playSound(st, hrp: BasePart, action: string)
		local def = cfg.sounds[action]
		if not def then
			return
		end
		local sound = st.sounds[action]
		if not sound or sound.Parent ~= hrp then
			sound = Instance.new("Sound")
			sound.Name = "NPCSystem_" .. action
			sound.RollOffMode = Enum.RollOffMode.Linear
			sound.RollOffMaxDistance = cfg.soundMaxDistance
			sound.Parent = hrp
			st.sounds[action] = sound
		end
		sound.SoundId = def.id
		sound.Volume = def.volume
		sound.PlaybackSpeed = def.speed
		sound:Play()
	end

	local function act(st, hrp: BasePart, action: string)
		emitNoise(hrp.Position, cfg.noiseRadius[action], action)
		playSound(st, hrp, action)
	end

	local function newState()
		return { sprint = false, sneak = false, dist = 0, lastPos = nil, airSince = nil, groundMode = "walk", sounds = {}, lastInput = 0 }
	end

	local function hookCharacter(player: Player, character: Model)
		local st = states[player]
		if not st then
			return
		end
		st.lastPos, st.dist, st.airSince, st.sounds = nil, 0, nil, {}
		local hum = character:WaitForChild("Humanoid", 10)
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if not hum or not hrp then
			return
		end
		table.insert(connections, hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				st.airSince = os.clock()
				act(st, hrp, "jump")
			elseif new == Enum.HumanoidStateType.Freefall then
				st.airSince = st.airSince or os.clock()
			elseif new == Enum.HumanoidStateType.Landed then
				if st.airSince and os.clock() - st.airSince >= cfg.minLandFallTime then
					act(st, hrp, "land")
				end
				st.airSince = nil
			elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
				st.airSince = nil
			end
		end))
	end

	local function addPlayer(player: Player)
		states[player] = newState()
		table.insert(connections, player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end))
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		addPlayer(p)
	end
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
	end))

	table.insert(connections, remote.OnServerEvent:Connect(function(player, sprint, sneak)
		local st = states[player]
		if not st or type(sprint) ~= "boolean" or type(sneak) ~= "boolean" then
			return
		end
		local now = os.clock()
		if now - st.lastInput < 0.03 then
			return
		end
		st.lastInput = now
		st.sprint, st.sneak = sprint, sneak
	end))

	table.insert(connections, RunService.Heartbeat:Connect(function()
		for player, st in pairs(states) do
			local character = player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				local airborne = hum.FloorMaterial == Enum.Material.Air
				if not airborne then
					local mode = if st.sprint then "sprint" elseif st.sneak then "sneak" else "walk"
					st.groundMode = mode
					local speed = cfg.speeds[mode]
					local resolver = cfg.speedResolver
					if resolver then
						local ok, custom = pcall(resolver, player, mode, speed)
						if not ok then
							warn("[NPCSystem] movement.speedResolver failed: " .. tostring(custom))
						elseif type(custom) == "number" and custom == custom and custom >= 0 and custom < math.huge then
							speed = custom
						end
					end
					hum.WalkSpeed = speed

					local pos = hrp.Position
					if hum.MoveDirection.Magnitude > 0.1 and st.lastPos then
						local d = math.sqrt((pos.X - st.lastPos.X) ^ 2 + (pos.Z - st.lastPos.Z) ^ 2)
						if d < 20 then
							st.dist += d
						end
						if st.dist >= cfg.stepDistance[mode] then
							st.dist = 0
							act(st, hrp, mode)
						end
					else
						st.dist = 0
					end
					st.lastPos = pos
				else
					st.lastPos = nil
				end
			end
		end
	end))

	return function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		table.clear(connections)
		table.clear(states)
	end
end

return MovementService
