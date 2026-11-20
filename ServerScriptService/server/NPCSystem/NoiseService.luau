--!nonstrict

local Rules = require(script.Parent.Rules)

local NoiseService = {}
NoiseService.__index = NoiseService

function NoiseService.new(getControllers: () -> { any }, onEmitted: ((any) -> ())?)
	return setmetatable({
		getControllers = getControllers,
		onEmitted = onEmitted,
		nextId = 0,
	}, NoiseService)
end

function NoiseService:emit(position: Vector3, volume: number, options: { tag: string? }?): (number?, string?)
	if typeof(position) ~= "Vector3" then
		return nil, "position must be a Vector3"
	end
	if not (Rules.isFinite(position.X) and Rules.isFinite(position.Y) and Rules.isFinite(position.Z)) then
		return nil, "position must be finite"
	end
	local ok, reason = Rules.validateNoise(volume)
	if not ok then
		return nil, reason
	end

	self.nextId += 1
	local event = {
		id = self.nextId,
		position = position,
		radius = volume,
		time = os.clock(),
		tag = options and options.tag or nil,
	}

	if self.onEmitted then
		self.onEmitted(event)
	end

	local heard = 0
	for _, ctrl in ipairs(self.getControllers()) do
		if ctrl:isActive() then
			local distance = (ctrl.root.Position - position).Magnitude
			if Rules.canHear(distance, volume, ctrl.profile.hearing) then
				heard += 1

				ctrl:hear({
					id = event.id,
					position = event.position,
					radius = event.radius,
					time = event.time,
					tag = event.tag,
					distance = distance,
				})
			end
		end
	end
	return heard, nil
end

return NoiseService
