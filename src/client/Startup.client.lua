local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")

local Common = game:GetService("ReplicatedStorage").MetaPortalCommon
local Config = require(Common.Config)

local ArriveRemoteEvent = Common.Remotes.Arrive
local PocketPermissionRemoteEvent = Common.Remotes.PocketPermission
local BookmarkEvent = Common.Remotes.Bookmark
local GotoEvent = Common.Remotes.Goto
local AddGhostEvent = Common.Remotes.AddGhost
local FirePortalEvent = Common.Remotes.FirePortal
local ReturnToLastPocketEvent = Common.Remotes.ReturnToLastPocket
local PocketNameRemoteFunction = Common.Remotes.PocketName

local localPlayer = Players.LocalPlayer

local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()

local gotoPortalGui = localPlayer.PlayerGui:WaitForChild("GotoPortalGui")
local newPocketGui = localPlayer.PlayerGui:WaitForChild("NewPocketGui")	
local teleportScreenGui = Common.TeleportScreenGui:Clone()

local function InitPortal(portal)
	local teleportPart = portal.PrimaryPart
	
	local db = false -- debounce
	local function onTeleportTouch(otherPart)
		if not otherPart then return end
		if not otherPart.Parent then return end

		local humanoid = otherPart.Parent:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
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
					
					if CollectionService:HasTag(portal, "metapocket") then
						teleportScreenGui.Portal.Value = portal
					end
					teleportScreenGui.Parent = localPlayer.PlayerGui
					
					FirePortalEvent:FireServer(portal)
				end
				wait(20)
				db = false
			end
		end
	end
	teleportPart.Touched:Connect(onTeleportTouch)
end

local portals = CollectionService:GetTagged(Config.PortalTag)

for _, portal in ipairs(portals) do
	InitPortal(portal)
end

CollectionService:GetInstanceAddedSignal(Config.PortalTag):Connect(function(portal)
	InitPortal(portal)
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
						local pocketCFrame = pocket.PrimaryPart.CFrame
						local newCFrame = pocketCFrame + pocketCFrame.LookVector * 10
						
						wait(0.1)
						
						localCharacter.PrimaryPart:PivotTo(newCFrame)
					end
				end
			end
		end
		
		ArriveRemoteEvent:FireServer(teleportData)
		
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
	
	local hasPocketPermission = false
	local adminEvents = game:GetService("ReplicatedStorage"):FindFirstChild("MetaAdmin")
	if adminEvents then
		local canWriteRF = adminEvents:WaitForChild("CanWrite")

		if canWriteRF then
			hasPocketPermission = canWriteRF:InvokeServer()
		end
	end

	PocketPermissionRemoteEvent:FireServer(hasPocketPermission)
end

-- Create the menu items
-- icon is https://fonts.google.com/icons?icon.query=door
if ReplicatedStorage:FindFirstChild("Icon") then
	local Icon = require(game:GetService("ReplicatedStorage").Icon)
	local Themes =  require(game:GetService("ReplicatedStorage").Icon.Themes)
	
	local idValue = workspace:FindFirstChild("PrivateServerKey")
	if idValue ~= nil then
		-- We are in a pocket
		locationName = PocketNameRemoteFunction:InvokeServer() or "Unknown"
		locationName = "In "..locationName
	else
		locationName = "At the root"
	end

	local icon = Icon.new()
	icon:setImage("rbxassetid://9277769559")
	icon:setLabel("Pockets")
	icon:set("dropdownSquareCorners", true)
	icon:setDropdown({
		Icon.new()
		:setLabel(locationName)
		:bindEvent("selected", function(self)
			self:deselect()
		end),
		Icon.new()
		:setLabel("Goto Pocket...")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			gotoPortalGui.Enabled = true
			wait(0.1)
			gotoPortalGui.TextBox:CaptureFocus()
		end)
		:bindEvent("deselected", function(self)
			gotoPortalGui.Enabled = false
		end)
		:bindToggleKey(Config.ShortcutKey),
		Icon.new()
		:setLabel("Return to Pocket")
		:bindEvent("selected", function(self)
			self:deselect()
			icon:deselect()
			ReturnToLastPocketEvent:FireServer()
		end)
	})
	icon:setTheme(Themes["BlueGradient"])
	
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