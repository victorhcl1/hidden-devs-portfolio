--[[
	Handles phone UI navigation, app open animations, and a per-player
	messaging experience on the client side.

	The script wires:
	- Phone home/app navigation.
	- Contact list population based on current Players.
	- Message history storage per contact.
	- UI updates when messages are sent/received through ChatRemote.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Grab the LocalPlayer and wait until their PlayerGui is ready so we can
-- reliably attach to the UI hierarchy without racing with replication.
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Phone root UI references; these are static containers that never change
-- during runtime, so we cache them once for fast access on every interaction.
local phoneUI = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")
local innerScreen = phoneFrame:WaitForChild("InnerScreen")
local appsArea = innerScreen:WaitForChild("AppsArea")
local homeButton = phoneFrame:WaitForChild("HomeButton")

-- RemoteEvent used to communicate chat actions with the server.
-- If this is nil, messaging simply becomes a no-op on this client.
local chatRemote = ReplicatedStorage:FindFirstChild("ChatRemote")

-- References to the specific Messages app screen and its internal UI
-- elements. These are toggled between "contacts list" and "chat" views.
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

--[[
	ChatHistory is an in-memory store that keeps a per-contact list of
	message objects. The key is a contact/player name, and the value is a
	sequential array of messages in the order they were processed.
]]
local ChatHistory = {}
ChatHistory.__index = ChatHistory

function ChatHistory.new()
	-- We use a metatable so all instances share the same method table
	-- but each has its own backing _data dictionary.
	local self = setmetatable({}, ChatHistory)
	self._data = {}
	return self
end

function ChatHistory:push(contactName_, msg)
	-- When pushing a new message, we lazily create the contact's
	-- history table the first time they receive or send a message.
	if not self._data[contactName_] then
		self._data[contactName_] = {}
	end

	-- Messages for that contact are simply appended, preserving order.
	table.insert(self._data[contactName_], msg)
end

function ChatHistory:get(contactName_)
	-- Reads are safe even if the contact has no history; we normalize
        -- that case by returning an empty table to simplify callers.
	return self._data[contactName_] or {}
end

function ChatHistory:clear(contactName_)
	-- Clearing just drops the contact's entry, which lets Lua garbage
	-- collect the underlying table when no other references exist.
	self._data[contactName_] = nil
end

--[[
	ContactRegistry maps a player name to its corresponding contact
	button instance. This lets us quickly find the button when we need
	to show or clear notification badges.
]]
local ContactRegistry = {}
ContactRegistry.__index = ContactRegistry

function ContactRegistry.new()
	local self = setmetatable({}, ContactRegistry)
	self._buttons = {}
	return self
end

function ContactRegistry:register(playerName, btn)
	-- Every time we create a contact button, we register it here using
	-- the immutable Player.Name string as the key.
	self._buttons[playerName] = btn
end

function ContactRegistry:get(playerName)
	-- Lookups are O(1) table access by player name.
	return self._buttons[playerName]
end

function ContactRegistry:reset()
	-- When rebuilding the list (e.g., on PlayerAdded/Removing), we
	-- discard the previous mapping to avoid stale references.
	self._buttons = {}
end

-- Single shared instances of history and registry for this client.
local history = ChatHistory.new()
local registry = ContactRegistry.new()

-- Tracks which contact (if any) is currently opened in the chat screen.
-- When nil, no specific conversation is active.
local currentChat = nil

--[[
	setAppsClickable toggles input interactivity on all app icons.

	This is used to temporarily block taps while an app is mid-animation
	or while a screen transition is happening, so we do not open multiple
	apps in parallel from spammy clicks.
]]
local function setAppsClickable(state)
	for _, child in ipairs(appsArea:GetChildren()) do
		-- We restrict to button-like objects so non-interactive UI
		-- elements are not affected by the Active/AutoButtonColor flags.
		if child:IsA("ImageButton") or child:IsA("TextButton") then
			child.Active = state
			child.AutoButtonColor = state
		end
	end
end

--[[
	closeAllAppScreens collapses every Frame whose name ends with
	"AppScreen", and then returns the UI back to the home grid.

	This centralizes the "only one app screen visible at a time" rule so
	other code does not need to remember to hide siblings manually.
]]
local function closeAllAppScreens()
	for _, child in ipairs(innerScreen:GetChildren()) do
		-- We use a naming convention (suffix "AppScreen") to decide which
		-- frames are treated as app pages instead of other UI children.
		if child:IsA("Frame") and child.Name:match("AppScreen") then
			child.Visible = false
		end
	end

	-- After closing all apps, re-enable tap targets and show the grid.
	setAppsClickable(true)
	appsArea.Visible = true
end

--[[
	The home button simply resets the device to its home state by
	calling closeAllAppScreens when clicked or tapped.
]]
homeButton.InputBegan:Connect(function(input)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		closeAllAppScreens()
	end
end)

--[[
	playAppOpenAnimation orchestrates a short "splash" animation for an
	app when it becomes visible.

	Instead of directly showing content, we:
	1. Reveal an overlay with a faded background.
	2. Tween the app logo from zero-size & fully transparent to a
	   visible size.
	3. Pause briefly to let the logo sit.
	4. Fade both the overlay background and logo back out.
	5. Hide the overlay so the app UI remains underneath.
]]
local function playAppOpenAnimation(appScreen_)
	local overlay = appScreen_:FindFirstChild("LoadingOverlay")
	if not overlay then
		return
	end

	local logo = overlay:FindFirstChild("AppLogo")
	if not logo or not logo:IsA("ImageLabel") then
		return
	end

	-- Initialize visual state before playing tweens so the animation is
	-- deterministic each time the app opens.
	overlay.Visible = true
	overlay.BackgroundTransparency = 0.4
	logo.ImageTransparency = 1
	logo.Size = UDim2.new(0, 0, 0, 0)

	-- Shared tween definitions for in/out phases.
	local tweenIn = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenOut = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- First tween: grow the logo to a fixed size and fade it in.
	local logoIn = TweenService:Create(logo, tweenIn, {
		Size = UDim2.new(0, 80, 0, 80),
		ImageTransparency = 0,
	})
	logoIn:Play()
	logoIn.Completed:Wait()

	-- Short hold so the user can actually register the logo visually.
	task.wait(0.12)

	-- Second phase: fade the dim overlay to fully transparent and
	-- fade the logo out in parallel.
	TweenService:Create(overlay, tweenOut, {
		BackgroundTransparency = 1,
	}):Play()

	local logoOut = TweenService:Create(logo, tweenOut, {
		ImageTransparency = 1,
	})
	logoOut:Play()
	logoOut.Completed:Wait()

	-- Once both tweens complete, we fully hide the overlay so clicks
	-- go directly to the app UI underneath.
	overlay.Visible = false
end

--[[
	Here we attach click handlers to every app icon present in the
	AppsArea. Each icon is expected to be a Button whose Name matches
	the app screen name prefix (e.g. "MessagesApp" -> "MessagesAppScreen").
]]
for _, appIcon in ipairs(appsArea:GetChildren()) do
	if (appIcon:IsA("ImageButton") or appIcon:IsA("TextButton")) and appIcon.Name:match("App") then
		appIcon.MouseButton1Click:Connect(function()
			-- Derive the corresponding screen by convention instead of
			-- storing per-icon references, which keeps the UI clean.
			local targetScreen = innerScreen:FindFirstChild(appIcon.Name .. "Screen")
			if not targetScreen then
				return
			end

			-- Reset all apps to hidden before showing the newly selected
			-- one, guaranteeing only one app is visible at a time.
			closeAllAppScreens()
			targetScreen.Visible = true

			-- Temporarily lock all app icons so the user cannot open a
			-- second app while the animation is still running.
			setAppsClickable(false)
			appsArea.Visible = false

			-- Run the splash animation specific to this app screen.
			playAppOpenAnimation(targetScreen)

			-- Some app screens can expose an "OpenedEvent" BindableEvent
			-- that runs app-specific initialization on open.
			local openedEvent = targetScreen:FindFirstChild("OpenedEvent")
			if openedEvent and openedEvent:IsA("BindableEvent") then
				openedEvent:Fire()
			end
		end)
	end
end

--[[
	setContactNotification visually toggles a small badge on a contact
	button. This is used to signal unread messages per contact.

	The registry gives us the button for a given player name; then we
	either construct the badge (if it does not exist) or destroy it.
]]
local function setContactNotification(playerName, hasNotification)
	local btn = registry:get(playerName)
	if not btn then
		return
	end

	local badge = btn:FindFirstChild("NotifyBadge")

	if hasNotification and not badge then
		-- We create a small circular Frame positioned in the top-right
		-- area of the contact button to act as the unread indicator.
		badge = Instance.new("Frame")
		badge.Name = "NotifyBadge"
		badge.Size = UDim2.new(0, 10, 0, 10)
		badge.Position = UDim2.new(1, -18, 0, 10)
		badge.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
		badge.BorderSizePixel = 0
		badge.ZIndex = 60
		badge.Parent = btn

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = badge
	elseif not hasNotification and badge then
		-- Removing the badge is enough to clear the "unread" state; we
		-- do not need additional flags because the history already
		-- persists all messages.
		badge:Destroy()
	end
end

--[[
	createMessageBubble instantiates a new bubble for a single message
	and inserts it at the bottom of the MessagesArea list.

	The bubble's alignment and color are computed based on whether the
	current local player sent the message (right/blue) or received it
	(left/dark).
]]
local function createMessageBubble(msg)
	local isMe = (msg.From == player.Name)

	-- Wrapper is a transparent frame that participates in the
	-- UIListLayout, letting Roblox automatically stack bubbles
	-- vertically and expand the area height as messages grow.
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.new(1, 0, 0, 0)
	wrapper.AutomaticSize = Enum.AutomaticSize.Y
	wrapper.ZIndex = 61
	wrapper.Parent = messagesArea

	-- The bubble itself is a left or right anchored frame depending on
	-- the sender, giving the classic chat layout.
	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.new(0.7, 0, 0, 0)
	bubble.BackgroundColor3 = if isMe
		then Color3.fromRGB(100, 150, 255)
		else Color3.fromRGB(28, 28, 30)
	bubble.BorderSizePixel = 0
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.ZIndex = 62
	bubble.AnchorPoint = if isMe then Vector2.new(1, 0) else Vector2.new(0, 0)
	bubble.Position = if isMe
		then UDim2.new(1, -10, 0, 0)
		else UDim2.new(0, 10, 0, 0)
	bubble.Parent = wrapper

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bubble

	-- Padding adds inner breathing room so text does not clamp to the
	-- bubble border.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = bubble

	-- The text label auto-sizes vertically to fit the full message, and
	-- the wrapper/bubble expand with it because of AutomaticSize.
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = msg.Text
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.ZIndex = 63
	label.Parent = bubble
end

--[[
	createContactButton builds the full visual for a single player in
	the contacts list and wires the click handler that opens the chat
	for that player.

	On click, it:
	- Sets the currentChat state.
	- Swaps from contactsList to chatScreen.
	- Rebuilds the MessagesArea UI from ChatHistory for that contact.
	- Clears that contact's notification badge.
]]
local function createContactButton(targetPlayer)
	local btn = Instance.new("TextButton")
	btn.Name = targetPlayer.Name
	btn.Size = UDim2.new(1, 0, 0, 70)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 30)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 52
	btn.Parent = contactsList

	-- Avatar image frame; at this stage we set a default look and later
	-- replace Image with the fetched thumbnail.
	local avatar = Instance.new("ImageLabel")
	avatar.Size = UDim2.new(0, 50, 0, 50)
	avatar.Position = UDim2.new(0, 10, 0, 10)
	avatar.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	avatar.ZIndex = 53
	avatar.Parent = btn

	-- Thumbnail retrieval is wrapped in pcall to guard against
	-- transient errors, falling back to a placeholder asset if needed.
	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(
			targetPlayer.UserId,
			Enum.ThumbnailType.AvatarBust,
			Enum.ThumbnailSize.Size150x150
		)
	end)
	avatar.Image = (ok and img ~= "") and img or "rbxassetid://11263217352"

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	-- DisplayName is the prominent top text for the contact row.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -150, 0, 25)
	nameLabel.Position = UDim2.new(0, 70, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = targetPlayer.DisplayName
	nameLabel.ZIndex = 53
	nameLabel.Parent = btn

	-- Username (with @) is secondary text giving a stable identifier.
	local usernameLabel = Instance.new("TextLabel")
	usernameLabel.Size = UDim2.new(1, -150, 0, 20)
	usernameLabel.Position = UDim2.new(0, 70, 0, 35)
	usernameLabel.BackgroundTransparency = 1
	usernameLabel.Font = Enum.Font.Gotham
	usernameLabel.TextSize = 13
	usernameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
	usernameLabel.Text = "@" .. targetPlayer.Name
	usernameLabel.ZIndex = 53
	usernameLabel.Parent = btn

	btn.MouseButton1Click:Connect(function()
		-- Selecting a contact switches the active context for both the
		-- header label and subsequent outgoing messages.
		currentChat = targetPlayer
		contactName.Text = targetPlayer.DisplayName

		-- Swap UI: hide the list and show the actual chat screen.
		contactsList.Visible = false
		chatScreen.Visible = true

		-- Before replaying history, clear previous message bubbles and
		-- install a fresh layout so new messages stack from top to bottom.
		messagesArea:ClearAllChildren()

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = messagesArea

		-- Opening a conversation means any unread messages for this
		-- contact are now "seen", so we drop the notification badge.
		setContactNotification(targetPlayer.Name, false)

		-- Hydrate the UI from the chat history so the conversation
		-- appears as a continuous thread for this contact.
		for _, storedMsg in ipairs(history:get(targetPlayer.Name)) do
			createMessageBubble(storedMsg)
		end
	end)

	-- Expose this button through the registry for external access
	-- (e.g., setting unread badges from message events).
	registry:register(targetPlayer.Name, btn)

	return btn
end

--[[
	refreshContacts rebuilds the entire contacts list from the live
	Players service.

	This is called:
	- On initial load.
	- Whenever a player joins.
	- Whenever a player leaves.

	We clear both the visual list and the registry mapping, then
	recreate one row per other player.
]]
local function refreshContacts()
	contactsList:ClearAllChildren()
	registry:reset()

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = contactsList

	for _, plr in ipairs(Players:GetPlayers()) do
		-- The local player is not included as a contact for themselves.
		if plr ~= player then
			createContactButton(plr)
		end
	end
end

-- Keep contacts synchronized with the dynamic player list by calling
-- refreshContacts whenever players join or leave the server.
Players.PlayerAdded:Connect(refreshContacts)
Players.PlayerRemoving:Connect(refreshContacts)

--[[
	The send button handler packages the current text into a message
	payload and forwards it to the server via ChatRemote.

	We enforce three preconditions before sending:
	1. The remote must exist.
	2. A currentChat must be selected.
	3. The input text cannot be empty.
]]
sendBtn.MouseButton1Click:Connect(function()
	if not chatRemote or not currentChat or inputBox.Text == "" then
		return
	end

	-- Snapshot the message text once to avoid racing with user edits
	-- while the event is being fired.
	local text = inputBox.Text
	inputBox.Text = ""

	-- The message packet uses "To" as the target player name and
	-- "Text" as the raw message body. The server is responsible for
	-- validating and routing this to the appropriate recipient(s).
	chatRemote:FireServer("SendMessage", {
		To = currentChat.Name,
		Text = text,
	})
end)

--[[
	If chatRemote exists, we hook into OnClientEvent to react to
	server-side broadcasts.

	The server is expected to fire:
	- action == "ReceiveMessage" with a `msg` table containing fields:
	  From (sender name), To (recipient name), Text (body).

	Here we:
	- Normalize which contact this message belongs to (otherName).
	- Push it into ChatHistory for that contact.
	- Either append a bubble to the open chat (if viewing that contact),
	  or set an unread notification badge (for incoming messages).
]]
if chatRemote then
	chatRemote.OnClientEvent:Connect(function(action, msg)
		if action ~= "ReceiveMessage" then
			return
		end

		-- Decide which "other" participant this message relates to from
		-- the local player's perspective. This ensures our history is
		-- always keyed by the name of the remote contact.
		local otherName
		if msg.From == player.Name then
			otherName = msg.To
		elseif msg.To == player.Name then
			otherName = msg.From
		else
			-- Messages not involving this client are ignored.
			return
		end

		-- Persist the message to the local history so the thread can be
		-- reconstructed later even if the user is not in the chat view.
		history:push(otherName, msg)

		-- If we are currently looking at this contact's chat, we render
		-- the message immediately into the MessagesArea.
		if currentChat and otherName == currentChat.Name then
			createMessageBubble(msg)
		-- Otherwise, if this message is directed at the local player,
		-- we mark the sender as having unread content.
		elseif msg.To == player.Name then
			setContactNotification(msg.From, true)
		end
	end)
end

--[[
	The back button in the chat header returns the user to the contacts
	list, clearing currentChat so subsequent sends are not misrouted.
]]
backBtn.MouseButton1Click:Connect(function()
	chatScreen.Visible = false
	contactsList.Visible = true
	currentChat = nil
end)

--[[
	Some app screens might not have an OpenedEvent pre-created in
	Studio. To make this robust, we ensure the MessagesAppScreen always
	exposes one, then we bind it to refreshContacts so each open keeps
	the list in sync.
]]
local openedEvent = appScreen:FindFirstChild("OpenedEvent")
if not openedEvent then
	openedEvent = Instance.new("BindableEvent")
	openedEvent.Name = "OpenedEvent"
	openedEvent.Parent = appScreen
end

openedEvent.Event:Connect(refreshContacts)

-- Perform an initial population of the contacts list as soon as the
-- script runs so the user sees all available players immediately.
refreshContacts()
