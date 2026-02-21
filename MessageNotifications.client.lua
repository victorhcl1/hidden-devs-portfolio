local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local phoneUI = playerGui:WaitForChild("PhoneUI")
local phoneFrame = phoneUI:WaitForChild("PhoneFrame")

phoneFrame.AnchorPoint = phoneFrame.AnchorPoint
local finalPos = phoneFrame.Position
local closedPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, 1.3, finalPos.Y.Offset)

local tweenInfoOpen = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local tweenInfoClose = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local isTweening = false

local function animateOpen()
	if isTweening then
		return
	end
	isTweening = true
	phoneFrame.Position = closedPos
	local tween = TweenService:Create(phoneFrame, tweenInfoOpen, {
		Position = finalPos
	})
	tween:Play()
	tween.Completed:Wait()
	isTweening = false
end

local function animateClose()
	if isTweening then
		return
	end
	isTweening = true
	local tween = TweenService:Create(phoneFrame, tweenInfoClose, {
		Position = closedPos
	})
	tween:Play()
	tween.Completed:Wait()
	isTweening = false
end

phoneUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	if phoneUI.Enabled then
		animateOpen()
	else
		animateClose()
	end
end)

