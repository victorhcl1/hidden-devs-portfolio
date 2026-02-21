local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local socialRemote = ReplicatedStorage:WaitForChild("SocialRemote")

local phoneUI = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")
local innerScreen = phoneFrame:WaitForChild("InnerScreen")
local appsArea = innerScreen:WaitForChild("AppsArea")
local homeButton = phoneFrame:WaitForChild("HomeButton")

local function closeAllAppScreens()
	for _, child in ipairs(innerScreen:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("AppScreen") then
			child.Visible = false
		end
	end
end

homeButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		closeAllAppScreens()
	end
end)

local appIcon = appsArea:WaitForChild("ChirperApp")
local appScreen = innerScreen:WaitForChild("ChirperAppScreen")
local header = appScreen:WaitForChild("Header")
local newPostButton = header:WaitForChild("NewPostButton")
local feedFrame = appScreen:WaitForChild("Feed")

local composeScreen = appScreen:WaitForChild("ComposeScreen")
local composeHeader = composeScreen:WaitForChild("ComposeHeader")
local cancelButton = composeHeader:WaitForChild("CancelButton")
local publishButton = composeHeader:WaitForChild("PublishButton")
local composeBox = composeScreen:WaitForChild("ComposeBox")
local countLabel = composeScreen:WaitForChild("CountLabel")

local MAX_LENGTH = 200

local function formatTime(timestamp)
	local date = os.date("!*t", timestamp)
	return string.format("%02d:%02d", date.hour, date.min)
end

local function createPostCard(post)
	local frame = Instance.new("Frame")
	frame.Name = post.Id
	frame.Parent = feedFrame
	frame.Size = UDim2.new(1, -16, 0, 0)
	frame.Position = UDim2.new(0, 8, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.ZIndex = 52

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local avatar = Instance.new("ImageLabel")
	avatar.Parent = frame
	avatar.Size = UDim2.new(0, 36, 0, 36)
	avatar.Position = UDim2.new(0, 0, 0, 0)
	avatar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	avatar.ZIndex = 53

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local author = Players:GetPlayerByUserId(post.UserId)
	if author then
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(author.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and img ~= "" then
			avatar.Image = img
		end
	end

	local textBlock = Instance.new("Frame")
	textBlock.Name = "TextBlock"
	textBlock.Parent = frame
	textBlock.BackgroundTransparency = 1
	textBlock.Position = UDim2.new(0, 44, 0, 0)
	textBlock.Size = UDim2.new(1, -44, 0, 0)
	textBlock.AutomaticSize = Enum.AutomaticSize.Y
	textBlock.ZIndex = 53

	local tbLayout = Instance.new("UIListLayout")
	tbLayout.Parent = textBlock
	tbLayout.FillDirection = Enum.FillDirection.Vertical
	tbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tbLayout.Padding = UDim.new(0, 2)

	local topLine = Instance.new("Frame")
	topLine.Name = "TopLine"
	topLine.Parent = textBlock
	topLine.BackgroundTransparency = 1
	topLine.Size = UDim2.new(1, 0, 0, 18)
	topLine.ZIndex = 53

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Parent = topLine
	nameLabel.Size = UDim2.new(1, -60, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 53
	nameLabel.Text = post.DisplayName or post.Name

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Parent = topLine
	timeLabel.Size = UDim2.new(0, 60, 1, 0)
	timeLabel.Position = UDim2.new(1, -60, 0, 0)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.Gotham
	timeLabel.TextSize = 12
	timeLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right
	timeLabel.ZIndex = 53
	timeLabel.Text = formatTime(post.Timestamp)

	local nickLabel = Instance.new("TextLabel")
	nickLabel.Parent = textBlock
	nickLabel.Size = UDim2.new(1, 0, 0, 16)
	nickLabel.BackgroundTransparency = 1
	nickLabel.Font = Enum.Font.Gotham
	nickLabel.TextSize = 12
	nickLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
	nickLabel.TextXAlignment = Enum.TextXAlignment.Left
	nickLabel.ZIndex = 53
	nickLabel.Text = "@" .. post.Name

	local body = Instance.new("TextLabel")
	body.Parent = textBlock
	body.Size = UDim2.new(1, 0, 0, 0)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 14
	body.TextColor3 = Color3.fromRGB(230, 230, 230)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Text = post.Text
	body.ZIndex = 53

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.Parent = textBlock
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 20)
	actions.ZIndex = 53

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.Parent = actions
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Padding = UDim.new(0, 16)

	local repostButton = Instance.new("TextButton")
	repostButton.Name = "RepostButton"
	repostButton.Parent = actions
	repostButton.Size = UDim2.new(0, 60, 1, 0)
	repostButton.BackgroundTransparency = 1
	repostButton.Font = Enum.Font.Gotham
	repostButton.TextSize = 14
	repostButton.TextXAlignment = Enum.TextXAlignment.Left
	repostButton.TextColor3 = Color3.fromRGB(180, 180, 180)
	repostButton.ZIndex = 53
	repostButton.Text = "🔁 " .. tostring(post.Reposts or 0)

	local likeButton = Instance.new("TextButton")
	likeButton.Name = "LikeButton"
	likeButton.Parent = actions
	likeButton.Size = UDim2.new(0, 60, 1, 0)
	likeButton.BackgroundTransparency = 1
	likeButton.Font = Enum.Font.Gotham
	likeButton.TextSize = 14
	likeButton.TextXAlignment = Enum.TextXAlignment.Left
	likeButton.TextColor3 = Color3.fromRGB(180, 180, 180)
	likeButton.ZIndex = 53
	likeButton.Text = "♡ " .. tostring(post.Likes or 0)

	frame:SetAttribute("PostId", post.Id)

	likeButton.MouseButton1Click:Connect(function()
		local pid = frame:GetAttribute("PostId")
		if pid then
			socialRemote:FireServer("ToggleLike", {
				PostId = pid
			})
		end
	end)

	repostButton.MouseButton1Click:Connect(function()
		local pid = frame:GetAttribute("PostId")
		if pid then
			socialRemote:FireServer("ToggleRepost", {
				PostId = pid
			})
		end
	end)

	return frame
end

local function loadInitialFeed(posts)
	feedFrame:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.Parent = feedFrame
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)

	for i = 1, #posts do
		createPostCard(posts[i])
	end
end

socialRemote.OnClientEvent:Connect(function(action, data)
	if action == "InitialFeed" then
		loadInitialFeed(data)
	elseif action == "NewPost" then
		local card = createPostCard(data)
		card.LayoutOrder = -data.Timestamp
	elseif action == "UpdateCounters" then
		local pid = data.PostId
		for _, child in ipairs(feedFrame:GetChildren()) do
			if child:IsA("Frame") and child:GetAttribute("PostId") == pid then
				local tb = child:FindFirstChild("TextBlock")
				if tb then
					local actions = tb:FindFirstChild("Actions")
					if actions then
						local rb = actions:FindFirstChild("RepostButton")
						local lb = actions:FindFirstChild("LikeButton")
						if rb then
							rb.Text = "🔁 " .. tostring(data.Reposts or 0)
						end
						if lb then
							lb.Text = "♡ " .. tostring(data.Likes or 0)
						end
					end
				end
				break
			end
		end
	end
end)

local function openCompose()
	composeBox.Text = ""
	countLabel.Text = "0 / " .. MAX_LENGTH
	composeScreen.Visible = true
end

local function closeCompose()
	composeScreen.Visible = false
end

composeBox:GetPropertyChangedSignal("Text"):Connect(function()
	local len = #composeBox.Text
	if len > MAX_LENGTH then
		composeBox.Text = string.sub(composeBox.Text, 1, MAX_LENGTH)
		len = MAX_LENGTH
	end
	countLabel.Text = string.format("%d / %d", len, MAX_LENGTH)
end)

publishButton.MouseButton1Click:Connect(function()
	local text = composeBox.Text
	if text == "" then
		return
	end
	socialRemote:FireServer("CreatePost", {
		Text = text
	})
	closeCompose()
end)

cancelButton.MouseButton1Click:Connect(function()
	closeCompose()
end)

appIcon.MouseButton1Click:Connect(function()
	closeAllAppScreens()
	appScreen.Visible = true
	if not feedFrame:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.Parent = feedFrame
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
	end
end)

newPostButton.MouseButton1Click:Connect(function()
	openCompose()
end)
