local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local chatRemote = ReplicatedStorage:WaitForChild("ChatRemote")
local messageHistory = {}

local function getChatTable(aName, bName)
	messageHistory[aName] = messageHistory[aName] or {}
	messageHistory[aName][bName] = messageHistory[aName][bName] or {}
	return messageHistory[aName][bName]
end

chatRemote.OnServerEvent:Connect(function(sender, action, data)
	if action ~= "SendMessage" then
		return
	end

	local toName = data.To
	local text = data.Text

	if not text or text == "" then
		return
	end

	local receiver = Players:FindFirstChild(toName)
	if not receiver then
		return
	end

	local msg = {
		From = sender.Name,
		FromDisplay = sender.DisplayName,
		To = toName,
		ToDisplay = receiver.DisplayName,
		Text = text,
		Time = os.time(),
	}

	table.insert(getChatTable(sender.Name, toName), msg)
	table.insert(getChatTable(toName, sender.Name), msg)

	chatRemote:FireClient(sender, "ReceiveMessage", msg)
	chatRemote:FireClient(receiver, "ReceiveMessage", msg)
end)
