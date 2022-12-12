local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local Common = ReplicatedStorage.MetaPortalCommon

local localPlayer = Players.LocalPlayer

local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()

local function StartBoardURLDisplay(boardPersistId)
	local screenGui = localPlayer.PlayerGui:FindFirstChild("BoardURLDisplay")
	if screenGui ~= nil then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardURLDisplay"

	local button = Instance.new("TextButton")
	button.Name = "OKButton"
	button.BackgroundColor3 = Color3.fromRGB(148,148,148)
	button.Size = UDim2.new(0,200,0,50)
	button.Position = UDim2.new(0.5,-100,0.5,150)
	button.Parent = screenGui
	button.BackgroundColor3 = Color3.fromRGB(0,162,0)
	button.TextColor3 = Color3.new(1,1,1)
	button.TextSize = 25
	button.Text = "OK"
	button.Activated:Connect(function()
		screenGui:Destroy()
	end)
	Instance.new("UICorner").Parent = button
	
	-- The URL for a board depends on whether we are in a pocket or not
	-- if we are not in a pocket, then we just specify boardPersistId,
	-- if we are in a pocket we also need to include the pocketId
	
	local dataString
	
    local isPocket = Common:GetAttribute("IsPocket")
	if isPocket then
		if Common:GetAttribute("PocketId") == nil then
			Common:GetAttributeChangedSignal("PocketId"):Wait()
		end

		local pocketId = Common:GetAttribute("PocketId")

		dataString = pocketId .. "-" .. boardPersistId
	else
		dataString = boardPersistId
	end

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.3
	textBox.Size = UDim2.new(0,600,0,200)
	textBox.Position = UDim2.new(0.5,-300,0.5,-100)
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.TextSize = 20
	textBox.Text = dataString -- prepend http://metauniservice.com:8080/?boardPersistId={}&pocketId={}
	textBox.TextWrapped = true
	textBox.TextEditable = false
	textBox.ClearTextOnFocus = false

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0,10)
	padding.PaddingTop = UDim.new(0,10)
	padding.PaddingRight = UDim.new(0,10)
	padding.PaddingLeft = UDim.new(0,10)
	padding.Parent = textBox

	textBox.Parent = screenGui

	screenGui.Parent = localPlayer.PlayerGui
end

local function EndBoardSelectMode()
	local boards = CollectionService:GetTagged("metaboard")

	for _, board in boards do
		if board:FindFirstChild("PersistId") == nil then continue end
		
		local boardPart = if board:IsA("Model") then board.PrimaryPart else board
		local c = boardPart:FindFirstChild("ClickTargetClone")
		if c ~= nil then
			c:Destroy()
		end
	end

	local screenGui = localPlayer.PlayerGui:FindFirstChild("BoardURLGui")
	if screenGui ~= nil then
		screenGui:Destroy()
	end
end

local function StartBoardSelectMode()
	local screenGui = localPlayer.PlayerGui:FindFirstChild("BoardURLGui")
	if screenGui ~= nil then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BoardURLGui"

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.BackgroundColor3 = Color3.fromRGB(148,148,148)
	cancelButton.Size = UDim2.new(0,200,0,50)
	cancelButton.Position = UDim2.new(0.5,-100,0.9,-50)
	cancelButton.Parent = screenGui
	cancelButton.TextColor3 = Color3.new(1,1,1)
	cancelButton.TextSize = 30
	cancelButton.Text = "Cancel"
	cancelButton.Activated:Connect(function()
		EndBoardSelectMode()
		screenGui:Destroy()
	end)
	Instance.new("UICorner").Parent = cancelButton

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.BackgroundColor3 = Color3.new(0,0,0)
	textLabel.BackgroundTransparency = 0.9
	textLabel.Size = UDim2.new(0,500,0,50)
	textLabel.Position = UDim2.new(0.5,-250,0,100)
	textLabel.TextColor3 = Color3.new(1,1,1)
	textLabel.TextSize = 25
	textLabel.Text = "Select a board"
	textLabel.Parent = screenGui

	screenGui.Parent = localPlayer.PlayerGui

	local boards = CollectionService:GetTagged("metaboard")

	for _, board in boards do
		if board:FindFirstChild("PersistId") == nil then continue end

		local boardPart = if board:IsA("Model") then board.PrimaryPart else board
		
		local clickClone = boardPart:Clone()
		for _, t in ipairs(CollectionService:GetTags(clickClone)) do
			CollectionService:RemoveTag(clickClone, t)
		end
		clickClone:ClearAllChildren()
		clickClone.Name = "ClickTargetClone"
		clickClone.Transparency = 0
		clickClone.Size = boardPart.Size * 1.02
		clickClone.Material = Enum.Material.SmoothPlastic
		clickClone.CanCollide = false
		clickClone.Parent = boardPart
		clickClone.Color = Color3.new(0.296559, 0.397742, 0.929351)
		clickClone.CFrame = boardPart.CFrame + boardPart.CFrame.LookVector * 1

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = 500
		clickDetector.Parent = clickClone
		clickDetector.MouseClick:Connect(function()
			StartBoardURLDisplay(board.PersistId.Value)
			EndBoardSelectMode()
		end)
	end
end

if ReplicatedStorage:FindFirstChild("Icon") then
	local Icon = require(game:GetService("ReplicatedStorage").Icon)
	local Themes =  require(game:GetService("ReplicatedStorage").Icon.Themes)

	local icon = Icon.new()
	icon:setImage("rbxassetid://11783868001")
	icon:setOrder(-1)
	icon:setLabel("")
	icon:set("dropdownSquareCorners", true)
	icon:set("dropdownMaxIconsBeforeScroll", 10)
	icon:setDropdown({
		Icon.new()
		:setLabel("Key for Board...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartBoardSelectMode()
		end)
	}) 

	icon:setTheme(Themes["BlueGradient"])
end