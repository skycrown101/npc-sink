local TownLife = require(game:GetService("ReplicatedStorage"):WaitForChild("TownLife"):WaitForChild("TownLife"))

TownLife.Start()

-- Optional hotkey to stop/start (for testing)
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F6 then
		TownLife.Stop()
	end
	if input.KeyCode == Enum.KeyCode.F7 then
		TownLife.Start()
	end
end)
