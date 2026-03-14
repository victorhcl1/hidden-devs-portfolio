--[[
	PhoneClient.lua  –  Client-side phone UI: navigation, messaging, animations.

	APIs demonstrated across this file:
	  • Players              – LocalPlayer, GetPlayers, GetUserThumbnailAsync
	  • ReplicatedStorage    – RemoteEvent wiring
	  • TweenService         – multi-phase UI animations
	  • UserInputService     – keyboard shortcuts (Enter / Escape)
	  • RunService           – Heartbeat-driven typing indicator & scroll polling
	  • SoundService         – notification / send sound playback
	  • TextService          – GetTextSize for dynamic bubble width
	  • ContextActionService – mobile back-gesture binding
	  • HttpService          – GenerateGUID for unique message IDs
	  • os.time / os.date    – message timestamps
	  • coroutines           – async typing-indicator lifecycle
	  • Metatables           – ChatHistory, ContactRegistry, NotificationQueue
]]

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. SERVICE REFERENCES
-- ─────────────────────────────────────────────────────────────────────────────

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local TweenService         = game:GetService("TweenService")
local UserInputService     = game:GetService("UserInputService")
local RunService           = game:GetService("RunService")
local SoundService         = game:GetService("SoundService")
local TextService          = game:GetService("TextService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService          = game:GetService("HttpService")

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CONSTANTS
-- ─────────────────────────────────────────────────────────────────────────────

-- How wide (in pixels) a message bubble can grow before text wraps.
local BUBBLE_MAX_WIDTH_PX  = 220
-- Font used throughout the chat view; cached so callers do not repeat it.
local CHAT_FONT            = Enum.Font.Gotham
-- Point size used when measuring text bounds via TextService.
local CHAT_FONT_SIZE       = 14
-- Roblox asset IDs for sound effects (replace with your own assets).
local SFX_NOTIFY_ID        = "rbxassetid://9120386446"
local SFX_SEND_ID          = "rbxassetid://9118823916"
-- Action name registered with ContextActionService for the back gesture.
local ACTION_BACK          = "PhoneBackAction"
-- Dot-count states used by the typing indicator animator.
local TYPING_DOT_FRAMES    = { ".", "..", "..." }

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. PLAYER & GUI REFERENCES
-- ─────────────────────────────────────────────────────────────────────────────

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Static phone frame references cached once at startup.
local phoneUI    = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")
local innerScreen = phoneFrame:WaitForChild("InnerScreen")
local appsArea   = innerScreen:WaitForChild("AppsArea")
local homeButton = phoneFrame:WaitForChild("HomeButton")

-- RemoteEvent for server communication; messaging becomes a no-op if absent.
local chatRemote = ReplicatedStorage:FindFirstChild("ChatRemote")

-- Messages-app sub-screens and their interactive children.
local appScreen   = innerScreen:WaitForChild("MessagesAppScreen")
local contactsList = appScreen:WaitForChild("ContactsList")
local chatScreen  = appScreen:WaitForChild("ChatScreen")
local chatHeader  = chatScreen:WaitForChild("ChatHeader")
local backBtn     = chatHeader:WaitForChild("BackButton")
local contactName = chatHeader:WaitForChild("ContactName")
local messagesArea = chatScreen:WaitForChild("MessagesArea")
local inputBar    = chatScreen:WaitForChild("InputBar")
local inputBox    = inputBar:WaitForChild("InputBox")
local sendBtn     = inputBar:WaitForChild("SendButton")

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SOUND SETUP
--    We create two Sound instances parented to SoundService so they are
--    positionally neutral (no spatial falloff) and reusable.
-- ─────────────────────────────────────────────────────────────────────────────

local function createSound(assetId, volume)
	local snd      = Instance.new("Sound")
	snd.SoundId    = assetId
	snd.Volume     = volume
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.Parent     = SoundService
	return snd
end

local notifySound = createSound(SFX_NOTIFY_ID, 0.4)
local sendSound   = createSound(SFX_SEND_ID,   0.3)

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CHATHISTORY  (metatable)
--    Stores per-contact message arrays keyed by Player.Name.
--    Extra methods: count, latest.
-- ─────────────────────────────────────────────────────────────────────────────

local ChatHistory = {}
ChatHistory.__index = ChatHistory

function ChatHistory.new()
	return setmetatable({ _data = {} }, ChatHistory)
end

-- Lazily creates the contact bucket and appends the message.
function ChatHistory:push(contactName_, msg)
	if not self._data[contactName_] then
		self._data[contactName_] = {}
	end
	table.insert(self._data[contactName_], msg)
end

-- Returns the full ordered message list, or an empty table when absent.
function ChatHistory:get(contactName_)
	return self._data[contactName_] or {}
end

-- Convenience: how many messages exist for a given contact.
function ChatHistory:count(contactName_)
	return #(self._data[contactName_] or {})
end

-- Convenience: the most recent message object, or nil when none exist.
function ChatHistory:latest(contactName_)
	local msgs = self._data[contactName_]
	return msgs and msgs[#msgs] or nil
end

-- Drops the contact's history, letting Lua GC reclaim the table.
function ChatHistory:clear(contactName_)
	self._data[contactName_] = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CONTACTREGISTRY  (metatable)
--    Maps Player.Name → contact TextButton for badge management.
-- ─────────────────────────────────────────────────────────────────────────────

local ContactRegistry = {}
ContactRegistry.__index = ContactRegistry

function ContactRegistry.new()
	return setmetatable({ _buttons = {}, _unread = {} }, ContactRegistry)
end

function ContactRegistry:register(playerName, btn)
	self._buttons[playerName] = btn
	self._unread[playerName]  = 0
end

function ContactRegistry:get(playerName)
	return self._buttons[playerName]
end

-- Increment unread counter and return the new value.
function ContactRegistry:incrementUnread(playerName)
	self._unread[playerName] = (self._unread[playerName] or 0) + 1
	return self._unread[playerName]
end

-- Reset unread counter when the user opens the conversation.
function ContactRegistry:clearUnread(playerName)
	self._unread[playerName] = 0
end

function ContactRegistry:getUnread(playerName)
	return self._unread[playerName] or 0
end

function ContactRegistry:reset()
	self._buttons = {}
	self._unread  = {}
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. NOTIFICATIONQUEUE  (metatable)
--    FIFO queue that batches badge updates so rapid incoming messages
--    from different senders do not thrash the UI on every event.
-- ─────────────────────────────────────────────────────────────────────────────

local NotificationQueue = {}
NotificationQueue.__index = NotificationQueue

function NotificationQueue.new()
	return setmetatable({ _queue = {}, _processing = false }, NotificationQueue)
end

-- Enqueue a player name; duplicates within a flush cycle are collapsed.
function NotificationQueue:enqueue(playerName)
	-- Avoid inserting the same sender twice inside a single frame.
	for _, name in ipairs(self._queue) do
		if name == playerName then return end
	end
	table.insert(self._queue, playerName)
end

-- Drain and return all pending names, clearing the internal list.
function NotificationQueue:flush()
	local snapshot = table.clone(self._queue)
	self._queue    = {}
	return snapshot
end

function NotificationQueue:isEmpty()
	return #self._queue == 0
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. SHARED INSTANCES
-- ─────────────────────────────────────────────────────────────────────────────

local history   = ChatHistory.new()
local registry  = ContactRegistry.new()
local notifQ    = NotificationQueue.new()

-- Tracks the Player object for the currently open conversation.
local currentChat = nil

-- Tracks the active RunService connection for the typing indicator so we
-- can disconnect it cleanly when the indicator is dismissed.
local typingConnection = nil

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. UTILITY HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

--[[
	formatTimestamp converts a Unix epoch (seconds) into a short string.
	os.date returns a table of date/time components which we format ourselves
	so the output locale is predictable regardless of the server region.
]]
local function formatTimestamp(epoch)
	local t    = os.date("*t", epoch)   -- returns a Lua date table
	local hour = t.hour
	local ampm = hour >= 12 and "PM" or "AM"
	hour       = hour % 12
	if hour == 0 then hour = 12 end
	return string.format("%d:%02d %s", hour, t.min, ampm)
end

--[[
	measureTextWidth uses TextService to predict how wide a string will
	render at CHAT_FONT / CHAT_FONT_SIZE.  We clamp the result so bubbles
	never exceed BUBBLE_MAX_WIDTH_PX.
]]
local function measureTextWidth(text)
	local bounds = TextService:GetTextSize(
		text,
		CHAT_FONT_SIZE,
		CHAT_FONT,
		Vector2.new(BUBBLE_MAX_WIDTH_PX, math.huge)
	)
	return math.min(bounds.X + 24, BUBBLE_MAX_WIDTH_PX)  -- 24px for padding
end

--[[
	scrollToBottom forces a ScrollingFrame to its lowest canvas position.
	Called after inserting a new bubble so the latest message is always
	visible without manual scrolling.
]]
local function scrollToBottom(scrollFrame)
	-- We defer by one frame using RunService.Heartbeat so AutomaticSize
	-- has already resolved before we read CanvasSize.Y.
	local conn
	conn = RunService.Heartbeat:Connect(function()
		conn:Disconnect()
		scrollFrame.CanvasPosition = Vector2.new(
			0,
			math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)
		)
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. APP NAVIGATION
-- ─────────────────────────────────────────────────────────────────────────────

local function setAppsClickable(state)
	for _, child in ipairs(appsArea:GetChildren()) do
		if child:IsA("ImageButton") or child:IsA("TextButton") then
			child.Active          = state
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
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		closeAllAppScreens()
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. APP-OPEN ANIMATION
--     Multi-phase tween: logo grows in → brief hold → overlay fades out.
-- ─────────────────────────────────────────────────────────────────────────────

local function playAppOpenAnimation(appScreen_)
	local overlay = appScreen_:FindFirstChild("LoadingOverlay")
	if not overlay then return end
	local logo = overlay:FindFirstChild("AppLogo")
	if not (logo and logo:IsA("ImageLabel")) then return end

	overlay.Visible              = true
	overlay.BackgroundTransparency = 0.4
	logo.ImageTransparency       = 1
	logo.Size                    = UDim2.new(0, 0, 0, 0)

	local easeOut = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local easeIn  = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local logoIn = TweenService:Create(logo, easeOut, {
		Size             = UDim2.new(0, 80, 0, 80),
		ImageTransparency = 0,
	})
	logoIn:Play()
	logoIn.Completed:Wait()
	task.wait(0.12)

	-- Fade overlay and logo out in parallel.
	TweenService:Create(overlay, easeIn, { BackgroundTransparency = 1 }):Play()
	local logoOut = TweenService:Create(logo, easeIn, { ImageTransparency = 1 })
	logoOut:Play()
	logoOut.Completed:Wait()
	overlay.Visible = false
end

-- Wire every app icon in AppsArea to its corresponding screen.
for _, appIcon in ipairs(appsArea:GetChildren()) do
	if (appIcon:IsA("ImageButton") or appIcon:IsA("TextButton"))
		and appIcon.Name:match("App")
	then
		appIcon.MouseButton1Click:Connect(function()
			local targetScreen = innerScreen:FindFirstChild(appIcon.Name .. "Screen")
			if not targetScreen then return end

			closeAllAppScreens()
			targetScreen.Visible = true
			setAppsClickable(false)
			appsArea.Visible = false

			playAppOpenAnimation(targetScreen)

			local openedEvent = targetScreen:FindFirstChild("OpenedEvent")
			if openedEvent and openedEvent:IsA("BindableEvent") then
				openedEvent:Fire()
			end
		end)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. NOTIFICATION BADGES
-- ─────────────────────────────────────────────────────────────────────────────

local function setContactNotification(playerName, hasNotification)
	local btn = registry:get(playerName)
	if not btn then return end

	local badge = btn:FindFirstChild("NotifyBadge")

	if hasNotification then
		-- Create the circular badge if it does not yet exist.
		if not badge then
			badge                    = Instance.new("Frame")
			badge.Name               = "NotifyBadge"
			badge.Size               = UDim2.new(0, 18, 0, 18)
			badge.Position           = UDim2.new(1, -22, 0, 8)
			badge.BackgroundColor3   = Color3.fromRGB(255, 70, 70)
			badge.BorderSizePixel    = 0
			badge.ZIndex             = 60
			badge.Parent             = btn

			local corner             = Instance.new("UICorner")
			corner.CornerRadius      = UDim.new(1, 0)
			corner.Parent            = badge

			-- Show unread count inside the badge label.
			local countLabel         = Instance.new("TextLabel")
			countLabel.Name          = "CountLabel"
			countLabel.Size          = UDim2.new(1, 0, 1, 0)
			countLabel.BackgroundTransparency = 1
			countLabel.Font          = Enum.Font.GothamBold
			countLabel.TextSize      = 10
			countLabel.TextColor3    = Color3.fromRGB(255, 255, 255)
			countLabel.ZIndex        = 61
			countLabel.Parent        = badge
		end

		-- Sync the displayed count with the registry.
		local count = registry:getUnread(playerName)
		local lbl   = badge:FindFirstChild("CountLabel")
		if lbl then
			lbl.Text = count > 99 and "99+" or tostring(count)
		end

		-- Animate the badge appearance with a quick pop-scale tween.
		badge.Size = UDim2.new(0, 0, 0, 0)
		TweenService:Create(badge,
			TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 18, 0, 18) }
		):Play()
	elseif badge then
		badge:Destroy()
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. TYPING INDICATOR
--     A coroutine cycles through dot-frames on RunService.Heartbeat, giving
--     a live "..." animation without blocking the main thread.
-- ─────────────────────────────────────────────────────────────────────────────

local typingLabel = nil   -- TextLabel injected into MessagesArea while active.

local function showTypingIndicator(senderDisplayName)
	-- Remove any pre-existing indicator before starting a new one.
	if typingLabel then
		typingLabel:Destroy()
		typingLabel = nil
	end
	if typingConnection then
		typingConnection:Disconnect()
		typingConnection = nil
	end

	-- Wrapper frame that mimics the incoming-bubble alignment.
	local wrapper          = Instance.new("Frame")
	wrapper.Name           = "TypingIndicatorWrapper"
	wrapper.BackgroundTransparency = 1
	wrapper.Size           = UDim2.new(1, 0, 0, 36)
	wrapper.LayoutOrder    = 9999   -- Ensure it sits below all history bubbles.
	wrapper.ZIndex         = 61
	wrapper.Parent         = messagesArea

	local bubble           = Instance.new("Frame")
	bubble.Size            = UDim2.new(0, 80, 0, 28)
	bubble.Position        = UDim2.new(0, 10, 0, 4)
	bubble.BackgroundColor3 = Color3.fromRGB(50, 50, 52)
	bubble.BorderSizePixel = 0
	bubble.ZIndex          = 62
	bubble.Parent          = wrapper

	local corner           = Instance.new("UICorner")
	corner.CornerRadius    = UDim.new(0, 12)
	corner.Parent          = bubble

	typingLabel            = Instance.new("TextLabel")
	typingLabel.Size       = UDim2.new(1, 0, 1, 0)
	typingLabel.BackgroundTransparency = 1
	typingLabel.Font       = Enum.Font.GothamBold
	typingLabel.TextSize   = 16
	typingLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	typingLabel.Text       = "."
	typingLabel.ZIndex     = 63
	typingLabel.Parent     = bubble

	scrollToBottom(messagesArea)

	-- Cycle dot frames on Heartbeat using a frame-counter accumulator.
	local frameIndex  = 1
	local accumulator = 0
	typingConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator = accumulator + dt
		if accumulator >= 0.4 then       -- advance every 0.4 s
			accumulator = 0
			frameIndex  = (frameIndex % #TYPING_DOT_FRAMES) + 1
			if typingLabel and typingLabel.Parent then
				typingLabel.Text = TYPING_DOT_FRAMES[frameIndex]
			end
		end
	end)
end

local function hideTypingIndicator()
	if typingConnection then
		typingConnection:Disconnect()
		typingConnection = nil
	end
	local wrapper = messagesArea:FindFirstChild("TypingIndicatorWrapper")
	if wrapper then wrapper:Destroy() end
	typingLabel = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. MESSAGE BUBBLE CREATION
--     Uses TextService to right-size each bubble and os.time for timestamps.
-- ─────────────────────────────────────────────────────────────────────────────

local function createMessageBubble(msg)
	local isMe     = (msg.From == player.Name)
	local msgText  = msg.Text
	local bubbleW  = measureTextWidth(msgText)  -- TextService call
	local timestamp = formatTimestamp(msg.Timestamp or os.time())

	-- Remove any residual typing indicator before adding a real bubble.
	hideTypingIndicator()

	-- Transparent wrapper lets UIListLayout stack bubbles vertically.
	local wrapper               = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.Size                = UDim2.new(1, 0, 0, 0)
	wrapper.AutomaticSize       = Enum.AutomaticSize.Y
	wrapper.ZIndex              = 61
	wrapper.Parent              = messagesArea

	local bubble                = Instance.new("Frame")
	bubble.Size                 = UDim2.new(0, bubbleW, 0, 0)
	bubble.BackgroundColor3     = isMe
		and Color3.fromRGB(100, 150, 255)
		or  Color3.fromRGB(28, 28, 30)
	bubble.BorderSizePixel      = 0
	bubble.AutomaticSize        = Enum.AutomaticSize.Y
	bubble.ZIndex               = 62
	bubble.AnchorPoint          = isMe and Vector2.new(1, 0) or Vector2.new(0, 0)
	bubble.Position             = isMe
		and UDim2.new(1, -10, 0, 0)
		or  UDim2.new(0, 10, 0, 0)
	bubble.Parent               = wrapper

	local corner                = Instance.new("UICorner")
	corner.CornerRadius         = UDim.new(0, 12)
	corner.Parent               = bubble

	local padding               = Instance.new("UIPadding")
	padding.PaddingTop          = UDim.new(0, 8)
	padding.PaddingBottom       = UDim.new(0, 8)
	padding.PaddingLeft         = UDim.new(0, 12)
	padding.PaddingRight        = UDim.new(0, 12)
	padding.Parent              = bubble

	local label                 = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, -24, 0, 0)
	label.BackgroundTransparency = 1
	label.Font                  = CHAT_FONT
	label.TextSize              = CHAT_FONT_SIZE
	label.TextColor3            = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.TextYAlignment        = Enum.TextYAlignment.Top
	label.TextWrapped           = true
	label.Text                  = msgText
	label.AutomaticSize         = Enum.AutomaticSize.Y
	label.ZIndex                = 63
	label.Parent                = bubble

	-- Timestamp label sits below the bubble, grey and small.
	local tsLabel               = Instance.new("TextLabel")
	tsLabel.Size                = UDim2.new(1, 0, 0, 14)
	tsLabel.Position            = isMe
		and UDim2.new(0, 0, 1, 2)
		or  UDim2.new(0, 10, 1, 2)
	tsLabel.BackgroundTransparency = 1
	tsLabel.Font                = Enum.Font.Gotham
	tsLabel.TextSize            = 11
	tsLabel.TextColor3          = Color3.fromRGB(130, 130, 130)
	tsLabel.TextXAlignment      = isMe
		and Enum.TextXAlignment.Right
		or  Enum.TextXAlignment.Left
	tsLabel.Text                = timestamp
	tsLabel.ZIndex              = 62
	tsLabel.Parent              = wrapper

	-- Animate the bubble sliding in from its respective side.
	local startPos = isMe
		and UDim2.new(1, 20, 0, 0)
		or  UDim2.new(0, -20, 0, 0)
	bubble.Position = startPos
	TweenService:Create(bubble,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = isMe and UDim2.new(1, -10, 0, 0) or UDim2.new(0, 10, 0, 0) }
	):Play()

	scrollToBottom(messagesArea)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. CONTACT BUTTON CREATION
-- ─────────────────────────────────────────────────────────────────────────────

local function createContactButton(targetPlayer)
	local btn               = Instance.new("TextButton")
	btn.Name                = targetPlayer.Name
	btn.Size                = UDim2.new(1, 0, 0, 70)
	btn.BackgroundColor3    = Color3.fromRGB(28, 28, 30)
	btn.BorderSizePixel     = 0
	btn.AutoButtonColor     = false
	btn.Text                = ""
	btn.ZIndex              = 52
	btn.Parent              = contactsList

	-- Hover highlight tween for a tactile feel.
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad),
			{ BackgroundColor3 = Color3.fromRGB(44, 44, 46) }
		):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad),
			{ BackgroundColor3 = Color3.fromRGB(28, 28, 30) }
		):Play()
	end)

	-- Avatar ImageLabel with async thumbnail fetch.
	local avatar            = Instance.new("ImageLabel")
	avatar.Size             = UDim2.new(0, 50, 0, 50)
	avatar.Position         = UDim2.new(0, 10, 0, 10)
	avatar.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	avatar.ZIndex           = 53
	avatar.Parent           = btn

	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(
			targetPlayer.UserId,
			Enum.ThumbnailType.AvatarBust,
			Enum.ThumbnailSize.Size150x150
		)
	end)
	avatar.Image = (ok and img ~= "") and img or "rbxassetid://11263217352"

	local avatarCorner      = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent     = avatar

	-- Primary display name label.
	local nameLabel         = Instance.new("TextLabel")
	nameLabel.Size          = UDim2.new(1, -150, 0, 25)
	nameLabel.Position      = UDim2.new(0, 70, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font          = Enum.Font.GothamBold
	nameLabel.TextSize      = 16
	nameLabel.TextColor3    = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text          = targetPlayer.DisplayName
	nameLabel.ZIndex        = 53
	nameLabel.Parent        = btn

	-- Secondary @username label for stable identity.
	local usernameLabel     = Instance.new("TextLabel")
	usernameLabel.Size      = UDim2.new(1, -80, 0, 20)
	usernameLabel.Position  = UDim2.new(0, 70, 0, 34)
	usernameLabel.BackgroundTransparency = 1
	usernameLabel.Font      = Enum.Font.Gotham
	usernameLabel.TextSize  = 13
	usernameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
	usernameLabel.Text      = "@" .. targetPlayer.Name
	usernameLabel.ZIndex    = 53
	usernameLabel.Parent    = btn

	-- Latest-message preview label updated whenever a new message arrives.
	local previewLabel      = Instance.new("TextLabel")
	previewLabel.Name       = "PreviewLabel"
	previewLabel.Size       = UDim2.new(1, -80, 0, 16)
	previewLabel.Position   = UDim2.new(0, 70, 0, 50)
	previewLabel.BackgroundTransparency = 1
	previewLabel.Font       = Enum.Font.Gotham
	previewLabel.TextSize   = 12
	previewLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
	previewLabel.TextXAlignment = Enum.TextXAlignment.Left
	previewLabel.TextTruncate   = Enum.TextTruncate.AtEnd
	previewLabel.ZIndex     = 53
	previewLabel.Parent     = btn

	-- Populate preview with the most recent stored message if any.
	local latestMsg = history:latest(targetPlayer.Name)
	if latestMsg then
		previewLabel.Text = latestMsg.Text
	end

	-- Open this contact's conversation when the button is tapped.
	btn.MouseButton1Click:Connect(function()
		currentChat        = targetPlayer
		contactName.Text   = targetPlayer.DisplayName
		contactsList.Visible = false
		chatScreen.Visible = true

		-- Flush and rebuild the messages area from persistent history.
		messagesArea:ClearAllChildren()
		local layout = Instance.new("UIListLayout")
		layout.Padding     = UDim.new(0, 8)
		layout.SortOrder   = Enum.SortOrder.LayoutOrder
		layout.Parent      = messagesArea

		registry:clearUnread(targetPlayer.Name)
		setContactNotification(targetPlayer.Name, false)

		for _, storedMsg in ipairs(history:get(targetPlayer.Name)) do
			createMessageBubble(storedMsg)
		end
	end)

	registry:register(targetPlayer.Name, btn)
	return btn
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. CONTACTS LIST REFRESH
-- ─────────────────────────────────────────────────────────────────────────────

local function refreshContacts()
	contactsList:ClearAllChildren()
	registry:reset()

	local layout        = Instance.new("UIListLayout")
	layout.SortOrder    = Enum.SortOrder.LayoutOrder
	layout.Parent       = contactsList

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			createContactButton(plr)
		end
	end
end

Players.PlayerAdded:Connect(refreshContacts)
Players.PlayerRemoving:Connect(refreshContacts)

-- ─────────────────────────────────────────────────────────────────────────────
-- 17. SEND LOGIC
--     Uses HttpService:GenerateGUID so every message has a unique ID that
--     the server can use for deduplication / ordering.
-- ─────────────────────────────────────────────────────────────────────────────

local function doSend()
	if not chatRemote or not currentChat then return end
	local text = inputBox.Text:match("^%s*(.-)%s*$")   -- trim whitespace
	if text == "" then return end
	inputBox.Text = ""

	-- GenerateGUID(false) omits curly braces for a clean 36-char UUID.
	local msgId = HttpService:GenerateGUID(false)

	sendSound:Play()

	chatRemote:FireServer("SendMessage", {
		To        = currentChat.Name,
		Text      = text,
		MessageId = msgId,
		Timestamp = os.time(),
	})
end

sendBtn.MouseButton1Click:Connect(doSend)

-- ─────────────────────────────────────────────────────────────────────────────
-- 18. KEYBOARD SHORTCUTS  (UserInputService)
--     Enter  → send the current message.
--     Escape → navigate back from the chat view to the contacts list.
-- ─────────────────────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- gameProcessed is true when the engine already consumed the key
	-- (e.g. a GUI TextBox absorbed a keystroke), so we skip in that case
	-- only for Escape; Enter is explicitly gated on inputBox focus instead.
	if input.KeyCode == Enum.KeyCode.Return then
		-- Only fire when the InputBox has focus to avoid sending on any Enter press.
		if UserInputService:GetFocusedTextBox() == inputBox then
			doSend()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape and not gameProcessed then
		-- Pressing Escape from the chat screen mirrors the Back button.
		if chatScreen.Visible then
			chatScreen.Visible    = false
			contactsList.Visible  = true
			currentChat           = nil
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 19. CONTEXT ACTION SERVICE  (mobile back-gesture / button)
--     Binds a "back" action to the Roblox back button on mobile and the
--     Backspace key on desktop so the chat can be dismissed without a mouse.
-- ─────────────────────────────────────────────────────────────────────────────

ContextActionService:BindAction(
	ACTION_BACK,
	function(_, inputState, _)
		-- We only care about the Begin state to avoid double-firing.
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if chatScreen.Visible then
			chatScreen.Visible   = false
			contactsList.Visible = true
			currentChat          = nil
			return Enum.ContextActionResult.Sink   -- consumed
		end
		return Enum.ContextActionResult.Pass       -- let others handle it
	end,
	false,                                         -- createTouchButton = false
	Enum.KeyCode.ButtonB,                          -- gamepad B
	Enum.KeyCode.Backspace                         -- keyboard fallback
)

-- ─────────────────────────────────────────────────────────────────────────────
-- 20. INCOMING MESSAGE HANDLER  (ChatRemote.OnClientEvent)
-- ─────────────────────────────────────────────────────────────────────────────

if chatRemote then
	chatRemote.OnClientEvent:Connect(function(action, msg)

		-- ── Typing indicator ─────────────────────────────────────────────
		if action == "TypingStarted" then
			-- Only show the indicator when we are in that contact's chat.
			if currentChat and msg.From == currentChat.Name then
				showTypingIndicator(msg.From)
			end
			return
		end

		if action == "TypingStopped" then
			if currentChat and msg.From == currentChat.Name then
				hideTypingIndicator()
			end
			return
		end

		-- ── Regular message ──────────────────────────────────────────────
		if action ~= "ReceiveMessage" then return end

		-- Determine the "other" participant from this client's perspective.
		local otherName
		if msg.From == player.Name then
			otherName = msg.To
		elseif msg.To == player.Name then
			otherName = msg.From
		else
			return   -- message does not involve this client
		end

		-- Stamp with current time if the server did not include a timestamp.
		if not msg.Timestamp then
			msg.Timestamp = os.time()
		end

		history:push(otherName, msg)

		-- Update the contact row's preview text, if the button exists.
		local btn = registry:get(otherName)
		if btn then
			local preview = btn:FindFirstChild("PreviewLabel")
			if preview then
				preview.Text = msg.Text
			end
		end

		if currentChat and otherName == currentChat.Name then
			-- Conversation is open: render immediately.
			createMessageBubble(msg)
		elseif msg.To == player.Name then
			-- Conversation is in the background: badge + sound.
			registry:incrementUnread(otherName)
			notifQ:enqueue(otherName)
			notifySound:Play()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 21. NOTIFICATION QUEUE DRAIN  (RunService.Heartbeat)
--     Rather than touching the DOM for every single incoming message,
--     we batch-flush the queue once per frame.  This keeps the frame
--     budget predictable under message bursts.
-- ─────────────────────────────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function()
	if notifQ:isEmpty() then return end
	for _, name in ipairs(notifQ:flush()) do
		setContactNotification(name, true)
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 22. BACK BUTTON (in-screen)
-- ─────────────────────────────────────────────────────────────────────────────

backBtn.MouseButton1Click:Connect(function()
	hideTypingIndicator()
	chatScreen.Visible   = false
	contactsList.Visible = true
	currentChat          = nil
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- 23. MESSAGES APP OPENED EVENT
-- ─────────────────────────────────────────────────────────────────────────────

local openedEvent = appScreen:FindFirstChild("OpenedEvent")
if not openedEvent then
	openedEvent        = Instance.new("BindableEvent")
	openedEvent.Name   = "OpenedEvent"
	openedEvent.Parent = appScreen
end

openedEvent.Event:Connect(refreshContacts)

-- ─────────────────────────────────────────────────────────────────────────────
-- 24. INITIAL POPULATION
-- ─────────────────────────────────────────────────────────────────────────────

refreshContacts()
