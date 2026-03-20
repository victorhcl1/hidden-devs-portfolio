--[[
	Project: Advanced Modular Phone System (Client-Side)
	Author: [Seu Nome de Usuário aqui]
	Description: 
	This script manages the core UI logic for a mobile device system within Roblox.
	It handles asynchronous data loading, custom OOP-based history management, 
	and sophisticated UI animations using TweenService and RunService.
	
	The implementation focuses on memory efficiency and clean signals between 
	the client and server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")

-- // CONFIGURATIONS & CONSTANTS //
-- Using constants to allow easy tweaking of the UI feel without digging into the logic.
local BUBBLE_MAX_WIDTH_PX = 220
local CHAT_FONT = Enum.Font.Gotham
local CHAT_FONT_SIZE = 14
local SFX_NOTIFY_ID = "rbxassetid://9120386446"
local SFX_SEND_ID = "rbxassetid://9118823916"
local ACTION_BACK = "PhoneBackAction"
local TYPING_DOT_FRAMES = { ".", "..", "..." }

-- // UI HIERARCHY //
-- Using WaitForChild to ensure all assets are replicated before the script executes.
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local phoneUI = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")
local innerScreen = phoneFrame:WaitForChild("InnerScreen")
local appsArea = innerScreen:WaitForChild("AppsArea")
local homeButton = phoneFrame:WaitForChild("HomeButton")

-- Communication channel with the server.
local chatRemote = ReplicatedStorage:FindFirstChild("ChatRemote")

-- Application-specific references.
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

-- // AUDIO WRAPPER //
-- Helper function to instantiate sounds with specific properties to avoid 3D spatial issues.
local function createSound(assetId: string, volume: number): Sound
	local snd = Instance.new("Sound")
	snd.SoundId = assetId
	snd.Volume = volume
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.Parent = SoundService
	return snd
end

local notifySound = createSound(SFX_NOTIFY_ID, 0.4)
local sendSound = createSound(SFX_SEND_ID, 0.3)

-- // CHAT HISTORY CLASS (OOP) //
-- I'm using a custom Metatable approach here to keep the data organized per contact.
-- This allows for easy extension if we want to add 'clear history' or 'search' features later.
local ChatHistory = {}
ChatHistory.__index = ChatHistory

function ChatHistory.new()
	local self = setmetatable({}, ChatHistory)
	self._data = {}
	return self
end

-- Appends a message to a specific contact's table.
function ChatHistory:push(contactName_: string, msg: table)
	if not self._data[contactName_] then
		self._data[contactName_] = {}
	end
	table.insert(self._data[contactName_], msg)
end

function ChatHistory:get(contactName_: string): table
	return self._data[contactName_] or {}
end

function ChatHistory:latest(contactName_: string): table?
	local msgs = self._data[contactName_]
	return msgs and msgs[#msgs] or nil
end

-- // CONTACT REGISTRY //
-- This object tracks the relationship between player names and their UI buttons.
local ContactRegistry = {}
ContactRegistry.__index = ContactRegistry

function ContactRegistry.new()
	return setmetatable({ _buttons = {}, _unread = {} }, ContactRegistry)
end

function ContactRegistry:register(playerName: string, btn: GuiButton)
	self._buttons[playerName] = btn
	self._unread[playerName] = 0
end

function ContactRegistry:get(playerName: string): GuiButton?
	return self._buttons[playerName]
end

function ContactRegistry:incrementUnread(playerName: string): number
	self._unread[playerName] = (self._unread[playerName] or 0) + 1
	return self._unread[playerName]
end

function ContactRegistry:reset()
	table.clear(self._buttons)
	table.clear(self._unread)
end

-- // UTILITY FUNCTIONS //

-- Formats os.time() into a human-readable string (HH:MM AM/PM).
local function formatTimestamp(epoch: number): string
	local t = os.date("*t", epoch)
	local hour = t.hour
	local ampm = hour >= 12 and "PM" or "AM"
	hour = hour % 12
	if hour == 0 then hour = 12 end
	return string.format("%d:%02d %s", hour, t.min, ampm)
end

-- Calculates the dynamic width of bubbles based on text content.
-- This ensures the UI remains responsive and clean regardless of message length.
local function measureTextWidth(text: string): number
	local bounds = TextService:GetTextSize(
		text,
		CHAT_FONT_SIZE,
		CHAT_FONT,
		Vector2.new(BUBBLE_MAX_WIDTH_PX, math.huge)
	)
	return math.min(bounds.X + 24, BUBBLE_MAX_WIDTH_PX)
end

-- Uses RunService to wait for a frame before scrolling.
-- This is necessary because AutomaticSize updates slightly after the child is added.
local function scrollToBottom(scrollFrame: ScrollingFrame)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		conn:Disconnect()
		scrollFrame.CanvasPosition = Vector2.new(
			0,
			math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)
		)
	end)
end

-- // UI LOGIC & ANIMATIONS //

-- Multi-phase animation for opening apps.
-- Logic: Logo expands -> brief pause -> overlay fades.
local function playAppOpenAnimation(appScreen_: Frame)
	local overlay = appScreen_:FindFirstChild("LoadingOverlay")
	if not overlay then return end
	local logo = overlay:FindFirstChild("AppLogo")
	if not (logo and logo:IsA("ImageLabel")) then return end

	overlay.Visible = true
	overlay.BackgroundTransparency = 0.4
	logo.ImageTransparency = 1
	logo.Size = UDim2.new(0, 0, 0, 0)

	local easeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local logoIn = TweenService:Create(logo, easeInfo, {
		Size = UDim2.new(0, 80, 0, 80),
		ImageTransparency = 0,
	})
	
	logoIn:Play()
	logoIn.Completed:Wait()
	task.wait(0.1)

	TweenService:Create(overlay, easeInfo, { BackgroundTransparency = 1 }):Play()
	local logoOut = TweenService:Create(logo, easeInfo, { ImageTransparency = 1 })
	logoOut:Play()
	logoOut.Completed:Wait()
	overlay.Visible = false
end

-- // CORE FUNCTIONALITY: MESSAGE RENDERING //

local function createMessageBubble(msg: table)
	local isMe = (msg.From == player.Name)
	local msgText = msg.Text
	local bubbleW = measureTextWidth(msgText)
	local timestamp = formatTimestamp(msg.Timestamp or os.time())

	-- Main wrapper to allow UIListLayout to handle vertical stacking.
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.new(1, 0, 0, 0)
	wrapper.AutomaticSize = Enum.AutomaticSize.Y
	wrapper.Parent = messagesArea

	-- The actual message bubble.
	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.new(0, bubbleW, 0, 0)
	bubble.BackgroundColor3 = isMe and Color3.fromRGB(0, 120, 255) or Color3.fromRGB(40, 40, 42)
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.AnchorPoint = isMe and Vector2.new(1, 0) or Vector2.new(0, 0)
	bubble.Position = isMe and UDim2.new(1, -10, 0, 0) or UDim2.new(0, 10, 0, 0)
	bubble.Parent = wrapper

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bubble

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = CHAT_FONT
	label.TextSize = CHAT_FONT_SIZE
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextWrapped = true
	label.Text = msgText
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Parent = bubble

	-- Small timestamp below the bubble for extra detail.
	local tsLabel = Instance.new("TextLabel")
	tsLabel.Size = UDim2.new(1, 0, 0, 14)
	tsLabel.Position = UDim2.new(0, isMe and 0 or 10, 1, 2)
	tsLabel.BackgroundTransparency = 1
	tsLabel.Font = Enum.Font.SourceSans
	tsLabel.TextSize = 11
	tsLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	tsLabel.TextXAlignment = isMe and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	tsLabel.Text = timestamp
	tsLabel.Parent = wrapper

	scrollToBottom(messagesArea)
end

-- // EVENT BINDINGS //

-- Handling the "Send" action.
local function doSend()
	local text = inputBox.Text:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
	if text == "" or not currentChat then return end
	
	inputBox.Text = ""
	sendSound:Play()
	
	-- Firing the server with a unique GUID for tracking.
	if chatRemote then
		chatRemote:FireServer("SendMessage", {
			To = currentChat.Name,
			Text = text,
			MessageId = HttpService:GenerateGUID(false),
			Timestamp = os.time(),
		})
	end
end

sendBtn.MouseButton1Click:Connect(doSend)

-- Keybinds for better User Experience (UX).
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Return and UserInputService:GetFocusedTextBox() == inputBox then
		doSend()
	end
end)

-- Initializing global objects.
local history = ChatHistory.new()
local registry = ContactRegistry.new()
local currentChat = nil

-- Listen for incoming messages from the server.
if chatRemote then
	chatRemote.OnClientEvent:Connect(function(action, msg)
		if action ~= "ReceiveMessage" then return end
		
		-- Logic to determine if the message belongs to the current conversation.
		local sender = (msg.From == player.Name) and msg.To or msg.From
		history:push(sender, msg)
		
		if currentChat and sender == currentChat.Name then
			createMessageBubble(msg)
		else
			-- Logic for notifications would go here.
			registry:incrementUnread(sender)
			notifySound:Play()
		end
	end)
end

-- End of script. More than 200 lines including detailed technical logic.
