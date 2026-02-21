local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local socialRemote = ReplicatedStorage:WaitForChild("SocialRemote")
local NotificationConfig = require(ReplicatedStorage:WaitForChild("NotificationConfig"))

local notificationsGui = playerGui:WaitForChild("MsgNotifications")
local container = notificationsGui:WaitForChild("ToastContainer")

local function createToastForTweet(post)
	if post.UserId == player.UserId then
		return
	end

	local cfg = NotificationConfig.Get(player)
	if not cfg.Chirper then
		return
	end

	local fromPlayerName = post.DisplayName or post.Name or "Alguém"

	local toast = Instance.new("Frame")
	toast.Name = "TweetToast"
	toast.Parent = container
	toast.Size = UDim2.new(1, 0, 0, 70)
	toast.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	toast.BackgroundTransparency = 0.1
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = toast

	local avatar = Instance.new("ImageLabel")
	avatar.Parent = toast
	avatar.Size = UDim2.new(0, 40, 0, 40)
	avatar.Position = UDim2.new(0, 0, 0, 10)
	avatar.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	avatar.ZIndex = 2

	local fromPlayer = Players:GetPlayerByUserId(post.UserId)
	if fromPlayer then
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(fromPlayer.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and img ~= "" then
			avatar.Image = img
		end
	end

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local title = Instance.new("TextLabel")
	title.Parent = toast
	title.Size = UDim2.new(1, -50, 0, 22)
	title.Position = UDim2.new(0, 50, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = fromPlayerName .. " postou no Chirper"

	local body = Instance.new("TextLabel")
	body.Parent = toast
	body.Size = UDim2.new(1, -50, 0, 24)
	body.Position = UDim2.new(0, 50, 0, 26)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 16
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = Color3.fromRGB(230, 230, 230)
	body.TextWrapped = true
	body.Text = post.Text

	toast.Position = UDim2.new(1, 300, 0, 0)
	toast.Transparency = 1

	local tweenIn = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
		Transparency = 0
	})
	tweenIn:Play()

	task.delay(4, function()
		local tweenOut = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, 300, 0, 0),
			Transparency = 1
		})
		tweenOut:Play()
		tweenOut.Completed:Wait()
		toast:Destroy()
	end)
end

socialRemote.OnClientEvent:Connect(function(action, data)
	if action == "NewPost" and typeof(data) == "table" then
		createToastForTweet(data)
	end
end)
