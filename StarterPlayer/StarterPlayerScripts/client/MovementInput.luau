--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remote = ReplicatedStorage:WaitForChild("MovementInputRemote", 30)
if not remote then
	return
end

local window = remote:GetAttribute("DoubleTapWindow") or 0.3
local lastWPress = -math.huge
local sprint, sneak = false, false

local function send()
	remote:FireServer(sprint, sneak)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.W then
		local now = os.clock()
		if now - lastWPress <= window then
			sprint = true
			send()
		end
		lastWPress = now
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sneak = true
		send()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W then
		if sprint then
			sprint = false
			send()
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sneak = false
		send()
	end
end)
