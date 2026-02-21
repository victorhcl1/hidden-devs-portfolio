local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NotificationConfig = require(ReplicatedStorage:WaitForChild("NotificationConfig"))

local phoneUI = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")
local innerScreen = phoneFrame:WaitForChild("InnerScreen")
local settingsScr = innerScreen:WaitForChild("SettingsAppScreen")
local content = settingsScr:WaitForChild("Content")

local whatsappToggle = content:WaitForChild("WhatsappToggle")
local chirperToggle  = content:WaitForChild("ChirperToggle")
local liveToggle     = content:WaitForChild("LiveToggle")

local function applyToggleVisual(button, enabled)
	if enabled then
		button.Text = "ON"
		button.BackgroundColor3 = Color3.fromRGB(50,180,90)
	else
		button.Text = "OFF"
		button.BackgroundColor3 = Color3.fromRGB(90,90,90)
	end
end

local function getCfg()
	local cfg = NotificationConfig.Get(player)
	if cfg.Whatsapp == nil then cfg.Whatsapp = true end
	if cfg.Chirper  == nil then cfg.Chirper  = true end
	if cfg.Live     == nil then cfg.Live     = true end
	return cfg
end

local function saveCfg(cfg)
	NotificationConfig.Set(player, cfg)
end

local function init()
	local cfg = getCfg()
	applyToggleVisual(whatsappToggle, cfg.Whatsapp)
	applyToggleVisual(chirperToggle,  cfg.Chirper)
	applyToggleVisual(liveToggle,     cfg.Live)
end

whatsappToggle.MouseButton1Click:Connect(function()
	local cfg = getCfg()
	cfg.Whatsapp = not cfg.Whatsapp
	saveCfg(cfg)
	applyToggleVisual(whatsappToggle, cfg.Whatsapp)
end)

chirperToggle.MouseButton1Click:Connect(function()
	local cfg = getCfg()
	cfg.Chirper = not cfg.Chirper
	saveCfg(cfg)
	applyToggleVisual(chirperToggle, cfg.Chirper)
end)

liveToggle.MouseButton1Click:Connect(function()
	local cfg = getCfg()
	cfg.Live = not cfg.Live
	saveCfg(cfg)
	applyToggleVisual(liveToggle, cfg.Live)
end)

init()
