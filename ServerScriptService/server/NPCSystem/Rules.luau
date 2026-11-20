--!nonstrict

local Rules = {}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
Rules.isFinite = isFinite

function Rules.validateNoise(volume: any): (boolean, string?)
	if not isFinite(volume) then
		return false, "volume must be a finite number"
	end
	if volume < 0 then
		return false, "volume must be >= 0"
	end
	return true, nil
end

function Rules.canHear(distance: number, volume: number, hearing: number): boolean
	if not (isFinite(distance) and isFinite(volume) and isFinite(hearing)) then
		return false
	end
	if distance < 0 then
		return false
	end
	if volume <= 0 or hearing <= 0 then
		return false
	end
	return distance <= math.min(volume, hearing)
end

Rules.States = {
	"Idle",
	"Chasing",
	"InvestigatingNoise",
	"GoingToLastSeen",
	"Searching",
	"Returning",
	"Disabled",
}

local function set(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

Rules.Transitions = {
	Idle = set({ "Chasing", "InvestigatingNoise", "Disabled" }),
	Chasing = set({ "InvestigatingNoise", "GoingToLastSeen", "Returning", "Idle", "Disabled" }),
	InvestigatingNoise = set({ "Searching", "InvestigatingNoise", "Chasing", "GoingToLastSeen", "Returning", "Idle", "Disabled" }),
	GoingToLastSeen = set({ "Searching", "Chasing", "InvestigatingNoise", "Returning", "Idle", "Disabled" }),
	Searching = set({ "Chasing", "InvestigatingNoise", "GoingToLastSeen", "Returning", "Idle", "Disabled" }),
	Returning = set({ "Idle", "Chasing", "InvestigatingNoise", "Disabled" }),
	Disabled = {},
}

function Rules.canTransition(from: string, to: string): boolean
	local row = Rules.Transitions[from]
	return row ~= nil and row[to] == true
end

return Rules
