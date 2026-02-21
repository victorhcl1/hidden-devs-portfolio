local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NotificationConfig = require(ReplicatedStorage:WaitForChild("NotificationConfig"))

local settingsRemote = ReplicatedStorage:FindFirstChild("SettingsRemote")
if not settingsRemote then
	settingsRemote = Instance.new("RemoteEvent")
	settingsRemote.Name = "SettingsRemote"
	settingsRemote.Parent = ReplicatedStorage
end

Players.PlayerAdded:Connect(function(player)
	local cfg = NotificationConfig.Get(player)
	settingsRemote:FireClient(player, "InitialConfig", cfg)
end)

settingsRemote.OnServerEvent:Connect(function(player, action, data)
	if action == "ToggleApp" and type(data) == "table" then
		if type(data.AppName) == "string" and type(data.Enabled) == "boolean" then
			if data.AppName == "Whatsapp" or data.AppName == "Chirper" or data.AppName == "Live" then
				local cfg = NotificationConfig.Get(player)
				cfg[data.AppName] = data.Enabled
				NotificationConfig.Set(player, cfg)
			end
		end
	elseif action == "SetBackground" and type(data) == "table" then
		if type(data.AssetId) == "string" then
			local cfg = NotificationConfig.Get(player)
			cfg.BackgroundAssetId = data.AssetId
			NotificationConfig.Set(player, cfg)
		end
	end
end)
