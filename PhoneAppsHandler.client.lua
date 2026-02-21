local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

local function playAppOpenAnimation(appScreen)
	local overlay = appScreen:FindFirstChild("LoadingOverlay")
	if not overlay then
		return
	end

	local logo = overlay:FindFirstChild("AppLogo")
	if not logo or not logo:IsA("ImageLabel") then
		return
	end

	overlay.Visible = true
	overlay.BackgroundTransparency = 0.4
	logo.ImageTransparency = 1
	logo.Size = UDim2.new(0, 0, 0, 0)

	local tweenInfoIn = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenInfoOut = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local sizeGoal = UDim2.new(0, 80, 0, 80)

	local tweenLogoIn = TweenService:Create(logo, tweenInfoIn, {
		Size = sizeGoal,
		ImageTransparency = 0
	})
	tweenLogoIn:Play()
	tweenLogoIn.Completed:Wait()

	task.wait(0.12)

	local tweenOverlayOut = TweenService:Create(overlay, tweenInfoOut, {
		BackgroundTransparency = 1
	})
	local tweenLogoOut = TweenService:Create(logo, tweenInfoOut, {
		ImageTransparency = 1
	})

	tweenOverlayOut:Play()
	tweenLogoOut:Play()
	tweenLogoOut.Completed:Wait()
	overlay.Visible = false
end

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

			playAppOpenAnimation(appScreen)

			local openedEvent = appScreen:FindFirstChild("OpenedEvent")
			if openedEvent and openedEvent:IsA("BindableEvent") then
				openedEvent:Fire()
			end
		end)
	end
end

local chatRemote = ReplicatedStorage:FindFirstChild("ChatRemote")

local msgAppIcon = appsArea:WaitForChild("MessagesApp")
local appScreen = innerScreen:WaitForChild("MessagesAppScreen")
local contactsList = appScreen:WaitForChild("ContactsList")
local chatScreen = appScreen:WaitForChild("ChatScreen")
local chatHeader = chatScreen:WaitForChild("ChatHeader")
local backBtn = chatHeader:WaitForChild("BackButton")
local contactName = chatHeader:WaitForChild("ContactName")
local messagesArea = chatScreen:WaitForChild("MessagesArea")
local inputBar = chatScreen:WaitForChild("InputBar")
local inputBox = inputBar:WaitForChild("InputBox")
local sendBtn = inputBar:WaitForChild("SendButton")

local contactButtons = {}
local currentChat = nil
local chatHistory = {}

local function setContactNotification(playerName, hasNotification)
	local btn = contactButtons[playerName]
	if not btn then
		return
	end

	local badge = btn:FindFirstChild("NotifyBadge")
	if hasNotification then
		if not badge then
			badge = Instance.new("Frame")
			badge.Name = "NotifyBadge"
			badge.Parent = btn
			badge.Size = UDim2.new(0, 10, 0, 10)
			badge.Position = UDim2.new(1, -18, 0, 10)
			badge.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
			badge.BorderSizePixel = 0
			badge.ZIndex = 60

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = badge
		end
	else
		if badge then
			badge:Destroy()
		end
	end
end

local function createMessageBubble(msg)
	local isMe = msg.From == player.Name

	local wrapper = Instance.new("Frame")
	wrapper.Parent = messagesArea
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.new(1, 0, 0, 0)
	wrapper.AutomaticSize = Enum.AutomaticSize.Y
	wrapper.ZIndex = 61

	local bubble = Instance.new("Frame")
	bubble.Parent = wrapper
	bubble.Size = UDim2.new(0.7, 0, 0, 0)
	bubble.BackgroundColor3 = isMe and Color3.fromRGB(100, 150, 255) or Color3.fromRGB(28, 28, 30)
	bubble.BorderSizePixel = 0
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.ZIndex = 62
	bubble.AnchorPoint = isMe and Vector2.new(1, 0) or Vector2.new(0, 0)
	bubble.Position = isMe and UDim2.new(1, -10, 0, 0) or UDim2.new(0, 10, 0, 0)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bubble

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = bubble

	local textLabel = Instance.new("TextLabel")
	textLabel.Parent = bubble
	textLabel.Size = UDim2.new(1, -24, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Gotham
	textLabel.TextSize = 14
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.TextWrapped = true
	textLabel.Text = msg.Text
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.ZIndex = 63
end

local function createContactButton(targetPlayer)
	local btn = Instance.new("TextButton")
	btn.Name = targetPlayer.Name
	btn.Parent = contactsList
	btn.Size = UDim2.new(1, 0, 0, 70)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 30)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 52

	local avatar = Instance.new("ImageLabel")
	avatar.Parent = btn
	avatar.Size = UDim2.new(0, 50, 0, 50)
	avatar.Position = UDim2.new(0, 10, 0, 10)
	avatar.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	avatar.ZIndex = 53

	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(targetPlayer.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and img ~= "" then
		avatar.Image = img
	else
		avatar.Image = "rbxassetid://11263217352"
	end

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Parent = btn
	nameLabel.Size = UDim2.new(1, -150, 0, 25)
	nameLabel.Position = UDim2.new(0, 70, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = targetPlayer.DisplayName
	nameLabel.ZIndex = 53

	local usernameLabel = Instance.new("TextLabel")
	usernameLabel.Parent = btn
	usernameLabel.Size = UDim2.new(1, -150, 0, 20)
	usernameLabel.Position = UDim2.new(0, 70, 0, 35)
	usernameLabel.BackgroundTransparency = 1
	usernameLabel.Font = Enum.Font.Gotham
	usernameLabel.TextSize = 13
	usernameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
	usernameLabel.Text = "@" .. targetPlayer.Name
	usernameLabel.ZIndex = 53

	btn.MouseButton1Click:Connect(function()
		currentChat = targetPlayer
		contactName.Text = targetPlayer.DisplayName

		contactsList.Visible = false
		chatScreen.Visible = true

		messagesArea:ClearAllChildren()
		local layout = Instance.new("UIListLayout")
		layout.Parent = messagesArea
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder

		setContactNotification(targetPlayer.Name, false)

		local history = chatHistory[targetPlayer.Name]
		if history then
			for _, msg in ipairs(history) do
				createMessageBubble(msg)
			end
		end
	end)

	contactButtons[targetPlayer.Name] = btn
	return btn
end

local function refreshContacts()
	contactsList:ClearAllChildren()
	contactButtons = {}

	local layout = Instance.new("UIListLayout")
	layout.Parent = contactsList
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			createContactButton(plr)
		end
	end
end

Players.PlayerAdded:Connect(refreshContacts)
Players.PlayerRemoving:Connect(refreshContacts)

sendBtn.MouseButton1Click:Connect(function()
	if not chatRemote then
		return
	end
	if not currentChat or inputBox.Text == "" then
		return
	end

	local text = inputBox.Text
	inputBox.Text = ""

	chatRemote:FireServer("SendMessage", {
		To = currentChat.Name,
		Text = text,
	})
end)

if chatRemote then
	chatRemote.OnClientEvent:Connect(function(action, msg)
		if action ~= "ReceiveMessage" then
			return
		end

		local otherName
		if msg.From == player.Name then
			otherName = msg.To
		elseif msg.To == player.Name then
			otherName = msg.From
		else
			return
		end

		chatHistory[otherName] = chatHistory[otherName] or {}
		table.insert(chatHistory[otherName], msg)

		if currentChat and otherName == currentChat.Name then
			createMessageBubble(msg)
		else
			if msg.To == player.Name then
				setContactNotification(msg.From, true)
			end
		end
	end)
end

backBtn.MouseButton1Click:Connect(function()
	chatScreen.Visible = false
	contactsList.Visible = true
	currentChat = nil
end)

local openedEvent = appScreen:FindFirstChild("OpenedEvent")
if not openedEvent then
	openedEvent = Instance.new("BindableEvent")
	openedEvent.Name = "OpenedEvent"
	openedEvent.Parent = appScreen
end

openedEvent.Event:Connect(function()
	refreshContacts()
end)

refreshContacts()