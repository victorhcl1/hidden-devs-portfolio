local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local socialRemote = ReplicatedStorage:FindFirstChild("SocialRemote")
if not socialRemote then
	socialRemote = Instance.new("RemoteEvent")
	socialRemote.Name = "SocialRemote"
	socialRemote.Parent = ReplicatedStorage
end

local MAX_LENGTH = 200
local posts = {}
local likes = {}
local reposts = {}

local function filterText(text, fromPlayer)
	local success, result = pcall(function()
		return TextService:FilterStringAsync(text, fromPlayer.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not success then
		return nil
	end

	local ok, filtered = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return nil
	end

	return filtered
end

local function addPost(player, rawText)
	if #rawText == 0 then
		return nil
	end
	if #rawText > MAX_LENGTH then
		rawText = string.sub(rawText, 1, MAX_LENGTH)
	end

	local filtered = filterText(rawText, player)
	if not filtered or #filtered == 0 then
		return nil
	end

	local post = {
		Id = tostring(os.time()) .. "_" .. tostring(player.UserId) .. "_" .. tostring(#posts + 1),
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		Text = filtered,
		Timestamp = os.time(),
		Likes = 0,
		Reposts = 0,
	}
	table.insert(posts, 1, post)
	return post
end

local function toggleCounter(counterTable, post, userId)
	counterTable[post.Id] = counterTable[post.Id] or {}
	local has = counterTable[post.Id][userId] == true
	if has then
		counterTable[post.Id][userId] = nil
	else
		counterTable[post.Id][userId] = true
	end
	return not has
end

local function findPostById(id)
	for _, p in ipairs(posts) do
		if p.Id == id then
			return p
		end
	end
end

local PlayersSrv = game:GetService("Players")

PlayersSrv.PlayerAdded:Connect(function(player)
	socialRemote:FireClient(player, "InitialFeed", posts)
end)

socialRemote.OnServerEvent:Connect(function(player, action, data)
	if action == "CreatePost" then
		if typeof(data) ~= "table" or typeof(data.Text) ~= "string" then
			return
		end
		local post = addPost(player, data.Text)
		if post then
			socialRemote:FireAllClients("NewPost", post)
		end
	elseif action == "ToggleLike" then
		if typeof(data) ~= "table" or typeof(data.PostId) ~= "string" then
			return
		end
		local post = findPostById(data.PostId)
		if not post then
			return
		end

		local added = toggleCounter(likes, post, player.UserId)
		if added then
			post.Likes += 1
		else
			post.Likes -= 1
			if post.Likes < 0 then
				post.Likes = 0
			end
		end

		socialRemote:FireAllClients("UpdateCounters", {
			PostId = post.Id,
			Likes = post.Likes,
			Reposts = post.Reposts,
		})
	elseif action == "ToggleRepost" then
		if typeof(data) ~= "table" or typeof(data.PostId) ~= "string" then
			return
		end
		local post = findPostById(data.PostId)
		if not post then
			return
		end

		local added = toggleCounter(reposts, post, player.UserId)
		if added then
			post.Reposts += 1
		else
			post.Reposts -= 1
			if post.Reposts < 0 then
				post.Reposts = 0
			end
		end

		socialRemote:FireAllClients("UpdateCounters", {
			PostId = post.Id,
			Likes = post.Likes,
			Reposts = post.Reposts,
		})
	end
end)

