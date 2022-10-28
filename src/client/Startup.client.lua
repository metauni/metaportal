local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Common = game:GetService("ReplicatedStorage").MetaPortalCommon
local Config = require(Common.Config)

local ArriveRemoteEvent = Common.Remotes.Arrive
local BookmarkEvent = Common.Remotes.Bookmark
local GotoEvent = Common.Remotes.Goto
local AddGhostEvent = Common.Remotes.AddGhost
local FirePortalEvent = Common.Remotes.FirePortal
local ReturnToLastPocketEvent = Common.Remotes.ReturnToLastPocket
local UnlinkPortalRemoteEvent = Common.Remotes.UnlinkPortal
local SetTeleportGuiRemoteEvent = Common.Remotes.SetTeleportGui

local localPlayer = Players.LocalPlayer

local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()

local gotoPortalGui = localPlayer.PlayerGui:WaitForChild("GotoPortalGui")
local newPocketGui = localPlayer.PlayerGui:WaitForChild("NewPocketGui")	
local teleportScreenGui = Common.TeleportScreenGui:Clone()

local portalTouchedConnections = {}

SetTeleportGuiRemoteEvent.OnClientEvent:Connect(function(pocket)
	local pocketImages = Config.PocketTeleportBackgrounds
	local function getPocketBackground(pocketName: string)
		local imageId = pocketImages["Alpha Cove"] -- default to Alpha Cove
		
		for name, image in pocketImages do
			if string.find(pocketName, name, 1, true) then
				imageId = image
			end
		end
		
		return imageId
	end

	local teleportGui = Common.PocketTeleportGui:Clone()
	teleportGui.PocketImage.Image = getPocketBackground(pocket)
	teleportGui.PocketName.Text = pocket
	
	StarterGui:SetCore("TopbarEnabled", false)
	teleportGui.Parent = localPlayer:FindFirstChild("PlayerGui")
	
	TeleportService:SetTeleportGui(teleportGui)

	if VRService.VREnabled then
		local colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Enabled = true
		colorCorrection.Parent = game.Lighting

		local tweenInfo = TweenInfo.new(
			2, -- Time
			Enum.EasingStyle.Linear, -- EasingStyle
			Enum.EasingDirection.Out, -- EasingDirection
			0, -- RepeatCount (when less than zero the tween will loop indefinitely)
			false, -- Reverses (tween will reverse once reaching it's goal)
			0 -- DelayTime
		)

		local tween = TweenService:Create(colorCorrection, tweenInfo, {Brightness = -1})

		tween:Play()
	end
end)

local function InitPortal(portal)
	local teleportPart = portal.PrimaryPart
	if teleportPart == nil then
		print("[MetaPortal] Attempting to init portal with nil PrimaryPart")
		return
	end
	
	local db = false -- debounce
	local function onTeleportTouch(otherPart)
		if not otherPart then return end
		if not otherPart.Parent then return end

		local humanoid = otherPart.Parent:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			-- Don't trigger a teleport when a VR player tries to draw
			-- on the portal with their hand
			if VRService.VREnabled then
				if otherPart.Name == "MetaChalk" or
						otherPart.Name == "RightHand" or
						otherPart.Name == "LeftHand" then
					return
				end
			end

			if not db then
				db = true
				local plr = Players:GetPlayerFromCharacter(otherPart.Parent)
				if plr and plr == localPlayer and not plr.PlayerGui:FindFirstChild("TeleportScreenGui") then	
					teleportPart.Sound:Play()
					
					for _, desc in ipairs(plr.Character:GetDescendants()) do
						if desc:IsA("BasePart") then
							desc.Transparency = 1
							desc.CastShadow = false
						end
					end
					
					-- Don't put up this GUI for pockets
					if not CollectionService:HasTag(portal, "metapocket") then
						teleportScreenGui.Parent = localPlayer.PlayerGui	
					end
					
					FirePortalEvent:FireServer(portal)
				end
				wait(20)
				db = false
			end
		end
	end
	local connection = teleportPart.Touched:Connect(onTeleportTouch)
	portalTouchedConnections[portal] = connection
end

local portals = CollectionService:GetTagged(Config.PortalTag)

for _, portal in ipairs(portals) do
	InitPortal(portal)
end

CollectionService:GetInstanceAddedSignal(Config.PortalTag):Connect(function(portal)
	InitPortal(portal)
end)

CollectionService:GetInstanceRemovedSignal(Config.PortalTag):Connect(function(portal)
	if portalTouchedConnections[portal] ~= nil then
		portalTouchedConnections[portal]:Disconnect()
		portalTouchedConnections[portal] = nil
	end
end)

if localCharacter then
	local teleportData = TeleportService:GetLocalPlayerTeleportData()
	if teleportData then
		if teleportData.TargetPersistId then
			-- Look for the pocket with this PersistId
			local pockets = CollectionService:GetTagged("metapocket")

			for _, pocket in ipairs(pockets) do
				if pocket:FindFirstChild("PersistId") then
					if pocket.PersistId.Value == teleportData.TargetPersistId then
						local newCFrame = pocket:GetPivot() * CFrame.new(0, 0, -10)
						
						wait(0.1)
						
						localCharacter.PrimaryPart:PivotTo(newCFrame)
					end
				end
			end
		end
	
		local start = game.Workspace:FindFirstChild("Start")
		
		if start and start:FindFirstChild("Label") then
			local pocketName = nil
			for key, value in pairs(Config.PlaceIdOfPockets) do
				if value == game.PlaceId then
					pocketName = key
				end
			end

			local labelText = ""

			if pocketName ~= nil then
				labelText = labelText .. pocketName
			end

			labelText = labelText .. " " .. tostring(teleportData.PocketCounter)

			start.Label.SurfaceGui.TextLabel.Text = labelText
		end
	end
end

local function canUnlinkPortal(portal)
	local isPocket = Common:GetAttribute("IsPocket")
	local pocketCreatorId = Common:GetAttribute("PocketCreatorId")
	local isAdmin = localPlayer:GetAttribute("metaadmin_isadmin")
	local canUnlink = false

	if isPocket then
		-- In a pocket you can unlink a portal if you created it, you
		-- own the pocket, or you have admin privileges
		canUnlink = (localPlayer.UserId == portal.CreatorId.Value) or
					(localPlayer.UserId == pocketCreatorId) or
					isAdmin
	else
		-- Outside of a pocket, you can unlink a portal if you created it
		-- or you are an admin
		canUnlink = (localPlayer.UserId == portal.CreatorId.Value) or
					isAdmin
	end

	return canUnlink
end

local function EndUnlinkPortalMode()
	local portals = CollectionService:GetTagged(Config.PortalTag)

	for _, portal in ipairs(portals) do
		if portal:FindFirstChild("CreatorId") == nil then continue end

		if not canUnlinkPortal(portal) then continue end

		local c = portal:FindFirstChild("ClickTargetClone")
		if c ~= nil then
			c:Destroy()
		end
	end

	local screenGui = localPlayer.PlayerGui:FindFirstChild("UnlinkPortalGui")
	if screenGui ~= nil then
		screenGui:Destroy()
	end
end

local function StartPocketURLMode()
	local screenGui = localPlayer.PlayerGui:FindFirstChild("PocketURLGui")
	if screenGui ~= nil then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PocketURLGui"

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

	local pocketName = HttpService:UrlEncode(Common:GetAttribute("PocketName"))

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = Color3.new(0,0,0)
	textBox.BackgroundTransparency = 0.3
	textBox.Size = UDim2.new(0,800,0,200)
	textBox.Position = UDim2.new(0.5,-400,0.5,-100)
	textBox.TextColor3 = Color3.new(1,1,1)
	textBox.TextSize = 20
	textBox.Text = "https://www.roblox.com/games/start?placeId=" .. Config.RootPlaceId .. "&launchData=pocket:" .. pocketName
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

local function StartUnlinkPortalMode()
	local screenGui = localPlayer.PlayerGui:FindFirstChild("UnlinkPortalGui")
	if screenGui ~= nil then return end
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UnlinkPortalGui"

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
		EndUnlinkPortalMode()
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
	textLabel.Text = "Select a pocket portal to unlink"
	textLabel.Parent = screenGui

	screenGui.Parent = localPlayer.PlayerGui

	local portals = CollectionService:GetTagged(Config.PortalTag)

	for _, portal in ipairs(portals) do
		if portal:FindFirstChild("CreatorId") == nil then continue end

		if not canUnlinkPortal(portal) then continue end

		local teleportPart = portal.PrimaryPart
		local clickClone = teleportPart:Clone()
		for _, t in ipairs(CollectionService:GetTags(clickClone)) do
			CollectionService:RemoveTag(clickClone, t)
		end
		clickClone:ClearAllChildren()
		clickClone.Name = "ClickTargetClone"
		clickClone.Transparency = 0
		clickClone.Size = teleportPart.Size * 1.01
		clickClone.Material = Enum.Material.SmoothPlastic
		clickClone.CanCollide = false
		clickClone.Parent = portal
		clickClone.Color = Color3.new(1,0,0)
		clickClone.CFrame = teleportPart.CFrame + teleportPart.CFrame.LookVector * 1

		local clickDetector = Instance.new("ClickDetector")
		clickDetector.Parent = clickClone
		clickDetector.MouseClick:Connect(function()
			UnlinkPortalRemoteEvent:FireServer(portal)
			EndUnlinkPortalMode()
		end)
	end
end

local function returnToRisingSea()

end

-- Create the menu items
-- icon is https://fonts.google.com/icons?icon.query=door
if ReplicatedStorage:FindFirstChild("Icon") then
	local Icon = require(game:GetService("ReplicatedStorage").Icon)
	local Themes =  require(game:GetService("ReplicatedStorage").Icon.Themes)
	
	if Common:GetAttribute("IsPocket") == nil then
		Common:GetAttributeChangedSignal("IsPocket"):Wait()
	end

	local locationName
	if Common:GetAttribute("IsPocket") then
		-- We are in a pocket
		if Common:GetAttribute("PocketName") == nil then
			Common:GetAttributeChangedSignal("PocketName"):Wait()
		end
		locationName = "In "..Common:GetAttribute("PocketName")
	else
		locationName = "At the root"
	end

	
	local icon = Icon.new()
	icon:setImage("rbxassetid://9277769559")
	icon:setLabel("Pockets")
	icon:setOrder(1)
	icon:set("dropdownSquareCorners", true)
	icon:set("dropdownMaxIconsBeforeScroll", 10)
	icon:setDropdown({
		Icon.new()
			:setLabel(locationName)
			:lock()
			:set("iconBackgroundTransparency", 1),
		Icon.new()
			:setLabel("Goto Pocket...")
			:bindEvent("selected", function(self)
				self:deselect()
				icon:deselect()
				gotoPortalGui.Enabled = true
				wait(0.1)
				gotoPortalGui.Frame.TextBox:CaptureFocus()
			end)
			:bindEvent("deselected", function(self)
				gotoPortalGui.Enabled = false
			end)
			:setTip("Goto Pocket (K)")
			:bindToggleKey(Config.ShortcutKey),
		Icon.new()
		:setLabel("Unlink Portal...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartUnlinkPortalMode()
		end)
	}) 

	if not Common:GetAttribute("IsPocket") then
		local backIcon = Icon.new()
		backIcon:setLabel("Back to Pocket")
		backIcon:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			ReturnToLastPocketEvent:FireServer()
		end)
		backIcon:join(icon, "dropdown")
	end

	if Common:GetAttribute("IsPocket") then
		local urlIcon = Icon.new()
		urlIcon:setLabel("URL for Pocket...")
		urlIcon:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			StartPocketURLMode()
		end)
		urlIcon:join(icon, "dropdown")
	end

	if Common:GetAttribute("IsPocket") then
		local urlIcon = Icon.new()
		urlIcon:setLabel("Goto The Rising Sea")
		urlIcon:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			GotoEvent:FireServer("The Rising Sea")
		end)
		urlIcon:join(icon, "dropdown")
	end
	
	icon:setTheme(Themes["BlueGradient"])
	
	SetTeleportGuiRemoteEvent.OnClientEvent:Connect(function()
		icon:setEnabled(false)
	end)

	gotoPortalGui.Changed:Connect(function()
		if not gotoPortalGui.Enabled then
			icon:deselect()
		end
	end)
end

AddGhostEvent.OnClientEvent:Connect(function(ghost, pocketName, pocketCounter)
	if localPlayer.Name == ghost.Name then return end
	
	-- Leave behind a proximity prompt to follow them
	local ghostPrompt = Instance.new("ProximityPrompt")
	ghostPrompt.Name = "GhostPrompt"
	ghostPrompt.ActionText = "Follow to Pocket"
	ghostPrompt.MaxActivationDistance = 8
	ghostPrompt.HoldDuration = 1
	ghostPrompt.ObjectText = "Ghost"
	ghostPrompt.RequiresLineOfSight = false
	ghostPrompt.Parent = ghost.PrimaryPart
	
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt == ghostPrompt then
			ghostPrompt.Enabled = false
			GotoEvent:FireServer(pocketName .. " " .. tostring(pocketCounter))
		end
	end)
end)