local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local phoneUI = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")
local innerScreen = phoneFrame:WaitForChild("InnerScreen")
local appsArea = innerScreen:WaitForChild("AppsArea")
local homeButton = phoneFrame:WaitForChild("HomeButton")

local function setAppsClickable(state)
	for _, child in ipairs(appsArea:GetChildren()) do
		if child:IsA("ImageButton") or child:IsA("TextButton") then
			child.Active = state
			child.AutoButtonColor = state
		end
	end
end

local function closeAllAppScreens()
	for _, child in ipairs(innerScreen:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("AppScreen") then
			child.Visible = false
		end
	end
	setAppsClickable(true)
	appsArea.Visible = true
end

homeButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		closeAllAppScreens()
	end
end)

for _, appIcon in ipairs(appsArea:GetChildren()) do
	if (appIcon:IsA("ImageButton") or appIcon:IsA("TextButton")) and appIcon.Name:match("App") then
		appIcon.MouseButton1Click:Connect(function()
			local appScreenName = appIcon.Name .. "Screen"
			local appScreen = innerScreen:FindFirstChild(appScreenName)
			if not appScreen then
				return
			end
			closeAllAppScreens()
			appScreen.Visible = true
			setAppsClickable(false)
			appsArea.Visible = false
			local openedEvent = appScreen:FindFirstChild("OpenedEvent")
			if openedEvent and openedEvent:IsA("BindableEvent") then
				openedEvent:Fire()
			end
		end)
	end
end
