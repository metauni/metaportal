-- When you step into a pocket portal for the first time, it creates a pocket (identified
-- uniquely by a PlaceId together with an integer, the PocketCounter) using TeleportService
-- ReserveServer. We have to remember the access code for the pocket, and this is stored
-- in the DataStore with a key specific to the particular portal.

-- A Pocket learns its identifier (i.e. PlaceId-PocketCounter) from the first player
-- who enters it, who carries with them the PocketCounter in their TeleportData. This
-- is then stored permanently to the DataStore

-- https://developer.roblox.com/en-us/articles/Teleporting-Between-Places

-- Services
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local HTTPService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

-- Requires
local Common = game:GetService("ReplicatedStorage").MetaPortalCommon
local Config = require(Common.Config)

-- Remote Events
local ArriveRemoteEvent = Common.Remotes.Arrive
local PocketPermissionRemoteEvent = Common.Remotes.PocketPermission
local GotoEvent = Common.Remotes.Goto
local AddGhostEvent = Common.Remotes.AddGhost
local CreatePocketEvent = Common.Remotes.CreatePocket
local FirePortalEvent = Common.Remotes.FirePortal
local PocketNameRemoteFunction = Common.Remotes.PocketName
local ReturnToLastPocketEvent = Common.Remotes.ReturnToLastPocket
local LinkPocketEvent = Common.Remotes.LinkPocket

local ghosts = game.Workspace:FindFirstChild("MetaPortalGhostsFolder")

if ghosts == nil then
	ghosts = Instance.new("Folder")
	ghosts.Name = "MetaPortalGhostsFolder"
	ghosts.Parent = game.Workspace
end

local function isPocket()
	return (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
end

local MetaPortal = {}
MetaPortal.__index = MetaPortal

function MetaPortal.Init()
	MetaPortal.TeleportData = {} -- stores information for each player teleporting in
	MetaPortal.PocketInit = false
	MetaPortal.PocketData = nil
	MetaPortal.PocketPermission = {}
	MetaPortal.PocketInitTouchConnections = {}
	
	-- Find all metaportals
	local portals = CollectionService:GetTagged(Config.PortalTag)

	for _, portal in ipairs(portals) do
		MetaPortal.InitPortal(portal)
	end
	
	CollectionService:GetInstanceAddedSignal(Config.PortalTag):Connect(function(portal)
		MetaPortal.InitPortal(portal)
	end)
	
	-- If we are not a pocket we initialise our pocket portals
	-- now, otherwise we wait until the pocket itself has been initialised
	if not isPocket() then
		MetaPortal.InitPocketPortals()
	end
	
	ArriveRemoteEvent.OnServerEvent:Connect(function(plr, data)
		MetaPortal.PlayerArrive(plr, data)
	end)
	
	PocketPermissionRemoteEvent.OnServerEvent:Connect(function(plr,data)
		MetaPortal.PocketPermission[plr.UserId] = data
	end)
	
	GotoEvent.OnServerEvent:Connect(function(plr,pocketText)
		MetaPortal.GotoPocketHandler(plr,pocketText)
	end)
	
	FirePortalEvent.OnServerEvent:Connect(function(plr,portal)
		MetaPortal.FirePortal(portal, plr)
	end)
	
	TeleportService.TeleportInitFailed:Connect(MetaPortal.TeleportFailed)
	CreatePocketEvent.OnServerEvent:Connect(MetaPortal.CreatePocket)
	LinkPocketEvent.OnServerEvent:Connect(MetaPortal.CreatePocketLink)
	PocketNameRemoteFunction.OnServerInvoke = MetaPortal.PocketName
	ReturnToLastPocketEvent.OnServerEvent:Connect(MetaPortal.ReturnToLastPocket)

	print("[MetaPortal] "..Config.Version.." initialised")
end

function MetaPortal.ReturnToLastPocket(player)
	local DataStore = DataStoreService:GetDataStore(Config.DataStoreTag)
	if not DataStore then
        print("[MetaPortal] DataStore not loaded")
        return
    end

	local returnToPocketKey = "return_" .. player.UserId

	local success, returnToPocketData
    success, returnToPocketData = pcall(function()
        return DataStore:GetAsync(returnToPocketKey)
    end)
    if not success then
        print("[MetaPortal] GetAsync fail for " .. returnToPocketKey .. " " .. returnToPocketData)
        return
    end

	if returnToPocketData == nil then
		print("[MetaPortal] No return to pocket data")
		return
	end

	local accessCode = returnToPocketData.AccessCode
	local placeId = returnToPocketData.PlaceId
	local pocketCounter = returnToPocketData.PocketCounter

	if accessCode == nil or placeId == nil or pocketCounter == nil then
		print("[MetaPortal] Invalid return to pocket data")
		return
	end

	-- Check that they are not "returning" to the current pocket
	if placeId == game.PlaceId and pocketCounter == MetaPortal.PocketData.PocketCounter then
		print("[MetaPortal] Attempted to return to current pocket, exiting")
		return
	end

	MetaPortal.GotoPocket(player, placeId, pocketCounter, accessCode)
end

function MetaPortal.TeleportFailed(player, teleportResult, errorMessage, placeId)
	print("[MetaPortal] Teleport failed for "..player.Name.." to place "..placeId.." : "..errorMessage)
	player:LoadCharacter()
end

-- passThrough means we are handing a player off to a pocket, and don't
-- want to make a ghost or show the interstitial GUI
function MetaPortal.GotoPocket(plr, placeId, pocketCounter, accessCode, passThrough)
	if passThrough == nil then passThrough = false end

	if not passThrough then
		local screenGui = Common.TeleportScreenGui:Clone()
		if plr == nil then
			print("[MetaPortal] Passed nil player to GotoPocket")
			return
		end
	
		screenGui.Parent = plr.PlayerGui
	end

	local character = plr.Character

	-- Make a ghost
	if character ~= nil and character.PrimaryPart ~= nil and not passThrough then
		local cFrame = character.PrimaryPart.CFrame
		character.Archivable = true
		local ghost = character:Clone()
		character.Archivable = false

		character:Destroy()
		for _, item in pairs(plr.Backpack:GetChildren()) do
			item:Destroy()
		end

		ghost.Name = plr.Name
		ghost:PivotTo(cFrame)

		for _, desc in ipairs(ghost:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1 - (0.2 * (1 - desc.Transparency))
				desc.CastShadow = false
			end
		end

		ghost.Parent = game.Workspace.MetaPortalGhostsFolder

		-- Figure out pocket name
		local pocketName
		for key, val in pairs(Config.PlaceIdOfPockets) do
			if val == placeId then
				pocketName = key
			end
		end
		
		AddGhostEvent:FireAllClients(ghost, pocketName, pocketCounter)

		local sound = Instance.new("Sound")
		sound.Name = "Sound"
		sound.Playing = false
		sound.RollOffMaxDistance = 100
		sound.RollOffMinDistance = 10
		sound.RollOffMode = Enum.RollOffMode.LinearSquare
		sound.SoundId = "rbxassetid://7864771146"
		sound.Volume = 0.3
		sound.Parent = ghost.PrimaryPart

		sound:Play()

		task.delay(60, function() ghost:Destroy() end)
	end

	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData = {
		OriginPlaceId = game.PlaceId,
		OriginJobId = game.JobId,
		PocketCounter = pocketCounter
	}

	MetaPortal.StoreReturnToPocketData(plr, placeId, pocketCounter, accessCode)

	teleportOptions.ReservedServerAccessCode = accessCode
	teleportOptions:SetTeleportData(teleportData)

	local success, errormessage = pcall(function()
		return TeleportService:TeleportAsync(placeId, {plr}, teleportOptions)
	end)
	if not success then
		print("[MetaPortal] TeleportAsync failed: ".. errormessage)
	end
end

function MetaPortal.StoreReturnToPocketData(plr, placeId, pocketCounter, accessCode)
	-- Store this as the most recent pocket for this player
	local DataStore = DataStoreService:GetDataStore(Config.DataStoreTag)
	if not DataStore then
        print("[MetaPortal] DataStore not loaded")
        return
    end

	if plr == nil or placeId == nil or pocketCounter == nil or accessCode == nil then
		print("[MetaPortal] Bad data passed to StoreReturnToPocketData")
		return
	end

	local returnToPocketData = {
		PocketCounter = pocketCounter,
		AccessCode = accessCode,
		PlaceId = placeId
	}
	local returnToPocketKey = "return_" .. plr.UserId
	local success, errormessage = pcall(function()
		return DataStore:SetAsync(returnToPocketKey, returnToPocketData)
	end)
	if not success then
		print("[MetaPortal] SetAsync fail for " .. returnToPocketKey .. " with ".. errormessage)
		return
	end
end

function MetaPortal.PocketDataFromPocketName(pocketText)
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	
	if pocketText == nil or string.len(pocketText) == 0 then
		print("[MetaPortal] Bad pocket name")
		return nil
	end
	
	local strParts = pocketText:split(" ")
	if #strParts <= 1 then
		print("[MetaPortal] Badly formed pocket name")
		return nil
	end
	
	local pocketCounter = tonumber(strParts[#strParts])
	if pocketCounter == nil then
		print("[MetaPortal] Extraction of pocket counter failed")
		return nil
	end
	
	table.remove(strParts, #strParts)
	
	local pocketName = ""
	for i, part in pairs(strParts) do
		pocketName = pocketName .. part
		if i < #strParts then
			pocketName = pocketName .. " "
		end
	end
	
	local placeId = Config.PlaceIdOfPockets[pocketName]
	if placeId == nil then
		print("[MetaPortal] User specified bad pocket name")
		return nil
	end
	
	local pocketKey = MetaPortal.KeyForPocket(placeId, pocketCounter)
	
	local success, pocketJSON
	success, pocketJSON = pcall(function()
		return DataStore:GetAsync(pocketKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for pocket " .. pocketKey .. " " .. pocketJSON)
		return
	end
	
	if not pocketJSON then
		print("[MetaPortal] This pocket does not exist yet")
		return nil
	end
		
	local pocketData = HTTPService:JSONDecode(pocketJSON)
	if pocketData == nil then
		print("[MetaPortal] Failed to decode pocketData")
		return nil
	end

	return placeId, pocketData
end

function MetaPortal.GotoPocketHandler(plr, pocketText, passThrough)
	if passThrough == nil then passThrough = false end
	local placeId, pocketData = MetaPortal.PocketDataFromPocketName(pocketText)
	if placeId == nil or pocketData == nil then return end
	
	if pocketData.AccessCode == nil or pocketData.PocketCounter == nil then
		print("[MetaPortal] Failed to read access code for pocket")
		return
	end
	
	if isPocket() then
		if placeId == game.PlaceId and pocketData.PocketCounter == MetaPortal.PocketData.PocketCounter then
			print("[MetaPortal] Attempted to goto current pocket, exiting")
			return
		end
	end

	MetaPortal.GotoPocket(plr, placeId, pocketData.PocketCounter, pocketData.AccessCode, passThrough)
end

function MetaPortal.InitPocketPortals()
	local pockets = CollectionService:GetTagged(Config.PocketTag)

	for _, pocket in ipairs(pockets) do
		MetaPortal.InitPocketPortal(pocket)
	end
end

-- Keys have length 50, placeIds are 10 digits, so pocketCounter
-- is at most 21 digits
function MetaPortal.KeyForPocket(placeId, pocketCounter)
	return "metapocket/pocket/"..placeId.."-"..pocketCounter
end

-- Attempt to recover the identity of this pocket from the DataStore
-- Recall that the identity of a pocket is determined by its PlaceId
-- and by the integer PocketCounter, but we only have access to the
-- latter from the person who created the pocket as they join it
function MetaPortal.InitPocket(data)
	if data == nil then
		print("[MetaPortal] Attempted to initialise pocket with nil data")
		return
	end

	local pocketCounter = data.PocketCounter
	
	if pocketCounter == nil then
		print("[MetaPortal] Insufficient information to initialise pocket")
		return
	end
	
	-- This data is used for interop with metaboard and metaadmin
	local idValue = workspace:FindFirstChild("PrivateServerKey")
	if not idValue then
		idValue = Instance.new("StringValue")
		idValue.Name = "PrivateServerKey"
		idValue.Value = game.PlaceId .. "-" .. data.PocketCounter
		idValue.Parent = workspace
		print("[MetaPortal] PrivateServerKey " .. idValue.Value)
	end
		
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	
	local pocketKey = MetaPortal.KeyForPocket(game.PlaceId, data.PocketCounter)

	local success, pocketJSON
	success, pocketJSON = pcall(function()
		return DataStore:GetAsync(pocketKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for pocket " .. pocketKey .. " " .. pocketJSON)
		return
	end
	
	local pocketData
	if not pocketJSON then
		-- This is the first time this pocket has started up
		pocketData = {}
		pocketData.PocketCounter = data.PocketCounter
		pocketData.AccessCode = data.AccessCode
		pocketData.CreatorId = data.CreatorId
		pocketData.ParentPlaceId = data.ParentPlaceId
		pocketData.ParentPocketCounter = data.ParentPocketCounter
		pocketData.ParentAccessCode = data.ParentAccessCode
		pocketData.ParentOriginPersistId = data.OriginPersistId
		
		local pocketJSON = HTTPService:JSONEncode(pocketData)
		DataStore:SetAsync(pocketKey,pocketJSON)
	else
		pocketData = HTTPService:JSONDecode(pocketJSON)
	end
	
	local creatorId = pocketData.CreatorId
	if not creatorId then
		print("[MetaPortal] Failed to find CreatorId in pocket")
	else
		local creatorValue = workspace:FindFirstChild("PocketCreatorId")
		if not creatorValue then
			creatorValue = Instance.new("IntValue")
			creatorValue.Name = "PocketCreatorId"
			creatorValue.Value = creatorId
			creatorValue.Parent = workspace
			print("[MetaPortal] PocketCreatorId " .. creatorId)
		end
	end
	
	MetaPortal.PocketData = pocketData
	MetaPortal.PocketInit = true
	
	MetaPortal.InitPocketPortals()
end

function MetaPortal.PocketName(player)
	if MetaPortal.PocketData == nil then
		print("[MetaPortal] Cannot return name of un-initialised pocket")
		return
	end

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

	labelText = labelText .. " " .. tostring(MetaPortal.PocketData.PocketCounter)

	return labelText
end

function MetaPortal.InitPortal(portal)
	if not portal.PrimaryPart then
		print("[MetaPortal] Portal has no PrimaryPart")
		return
	end
	
	local teleportPart = portal.PrimaryPart
	
	teleportPart.Material = Enum.Material.Slate
	teleportPart.Transparency = 0.45
	teleportPart.CastShadow = 0
	teleportPart.CanCollide = false
	teleportPart.Anchored = true
	teleportPart.Color  = Color3.fromRGB(163, 162, 165)
	
	local sound = Instance.new("Sound")
	sound.Name = "Sound"
	sound.Playing = false
	sound.RollOffMaxDistance = 100
	sound.RollOffMinDistance = 10
	sound.RollOffMode = Enum.RollOffMode.LinearSquare
	sound.SoundId = "rbxassetid://7864771146"
	sound.Volume = 0.3
	sound.Parent = teleportPart
	
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(236, 139, 70)
	fire.Enabled = true
	fire.Heat = 9
	fire.Name = "Fire"
	fire.SecondaryColor = Color3.fromRGB(139, 80, 55)
	fire.Size = 5
	fire.Parent = teleportPart
	
	-- NOTE: Attaching touch events is now done on the client
end

function MetaPortal.FirePortal(portal, plr)
	if portal == nil or plr == nil then
		print("[MetaPortal] FirePortal passed nil inputs")
		return
	end

	local teleportPart = portal.PrimaryPart
	if teleportPart == nil then
		print("[MetaPortal] Portal has nil PrimaryPart")
		return
	end

	-- If the portal specifies a pocket name, hand it off
	if portal:FindFirstChild("PocketName") then
		MetaPortal.GotoPocketHandler(plr,portal.PocketName.Value)
		return
	end

	local placeId = portal.PlaceId.Value
	local returnPortal = portal:FindFirstChild("Return") and portal.Return.Value
	local playerTeleportData = MetaPortal.TeleportData[plr.UserId]
	
	--teleportPart.Sound:Play()
	
	plr.Character:Destroy()
	for _, item in pairs(plr.Backpack:GetChildren()) do
		item:Destroy()
	end

	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData = {
		OriginPlaceId = game.PlaceId,
		OriginJobId = game.JobId
	}
	
	-- If the portal leads to a pocket
	if CollectionService:HasTag(portal, "metapocket") then
		teleportData.OriginPersistId = portal.PersistId.Value -- portal you came from
		teleportData.PocketCounter = portal.PocketCounter.Value
		teleportData.CreatorId = portal.CreatorId.Value
		teleportData.AccessCode = portal.AccessCode.Value
		teleportData.ParentPlaceId = game.PlaceId -- TODO
		
		teleportOptions.ReservedServerAccessCode = portal.AccessCode.Value
		
		if isPocket() then	
			-- Pass along our identifying information so the sub-pocket can link back to us
			teleportData.ParentPocketCounter = MetaPortal.PocketData.PocketCounter
			teleportData.ParentAccessCode = MetaPortal.PocketData.AccessCode
		end

		MetaPortal.StoreReturnToPocketData(plr, placeId, portal.PocketCounter.Value, portal.AccessCode.Value)
	elseif returnPortal and isPocket() then
		-- If this is a "return to parent" portal, pass with the TeleportData the particular
		-- portal on the endpoint to teleport to (= where we came from). Recall
		-- that portals are identified by their PersistId

		-- The parent may be a top level server (so all we need is a place ID)
		-- or it could be a pocket itself, in which case we need its PlaceId
		-- PocketCounter and also its access code
		local u = MetaPortal.PocketData.ParentPlaceId
		local v = MetaPortal.PocketData.ParentPocketCounter
		local w = MetaPortal.PocketData.ParentAccessCode
		
		teleportData.TargetPersistId = MetaPortal.PocketData.ParentOriginPersistId
		
		if not u then
			print("[MetaPortal] Badly configured pocket")
			return
		end
		
		placeId = u
		
		if v and w then
			-- The parent is a pocket
			teleportData.PocketCounter = v
			teleportData.AccessCode = w
			teleportOptions.ReservedServerAccessCode = w

			MetaPortal.StoreReturnToPocketData(plr, placeId, v, w)
		end
	end
	
	teleportOptions:SetTeleportData(teleportData)
	
	local success, errormessage = pcall(function()
		return TeleportService:TeleportAsync(placeId, {plr}, teleportOptions)
	end)
	if not success then
		print("[MetaPortal] TeleportAsync failed: ".. errormessage)
	end
end

function MetaPortal.HasPocketPermission(plr)
	return MetaPortal.PocketPermission[plr.UserId]	
end

function MetaPortal.CreatePocketLink(plr, portal, pocketText)
	if portal == nil then
		print("[MetaPortal] Passed bad portal")
		return
	end

	if pocketText == nil or pocketText == "" then
		print("[MetaPortal] Passed bad pocketText to CreatePocketLink")
		return
	end

	local placeId, pocketData = MetaPortal.PocketDataFromPocketName(pocketText)
	if placeId == nil or pocketData == nil then
		print("[MetaPortal] Failed to find pocket data")
		return
	end

	if isPocket() then
		if placeId == game.PlaceId and pocketData.PocketCounter == MetaPortal.PocketData.PocketCounter then
			print("[MetaPortal] Attempted to link to current pocket, exiting")
			return
		end
	end
	
	pocketData.PlaceId = placeId
	pocketData.PocketName = Players:GetNameFromUserIdAsync(pocketData.CreatorId)

	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	local portalKey = MetaPortal.KeyForPortal(portal)
	local pocketJSON = HTTPService:JSONEncode(pocketData)
	DataStore:SetAsync(portalKey,pocketJSON)

	MetaPortal.AttachValuesToPocketPortal(portal, pocketData)
	local connection = MetaPortal.PocketInitTouchConnections[portal]
	if connection ~= nil then
		connection:Disconnect()
	end
end

function MetaPortal.CreatePocket(plr, portal, pocketChosen)
	if portal == nil then
		print("[MetaPortal] CreatePocket passed a nil portal")
		return
	end
	
	if pocketChosen == nil then
		print("[MetaPortal] Pocket chosen is nil")
		return
	end
	
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	local portalKey = MetaPortal.KeyForPortal(portal)
	
	local placeId = Config.PlaceIdOfPockets[pocketChosen]
	if placeId == nil then
		print("[MetaPortal] Could not find selected pocket type")
		return
	end

	local placeKey = "metapocket/place/"..placeId

	-- Increment the counter for this place
	local success, pocketCounter = pcall(function()
		return DataStore:IncrementAsync(placeKey, 1)
	end)
	if success then
		print("[MetaPortal] PlaceID counter is now "..pocketCounter)
	end

	local accessCode = TeleportService:ReserveServer(placeId)
	local pocketData = {
		AccessCode = accessCode,
		CreatorId = plr.UserId,
		PocketName = plr.DisplayName,
		PlaceId = placeId,
		ParentPlaceId = game.PlaceId,
		PocketCounter = pocketCounter
	}

	local pocketJSON = HTTPService:JSONEncode(pocketData)

	DataStore:SetAsync(portalKey,pocketJSON)

	MetaPortal.AttachValuesToPocketPortal(portal, pocketData)
	local connection = MetaPortal.PocketInitTouchConnections[portal]
	if connection ~= nil then
		connection:Disconnect()
	end
end

function MetaPortal.AttachValuesToPocketPortal(portal, data)
	local accessCode = Instance.new("StringValue")
	accessCode.Name = "AccessCode"
	accessCode.Value = data.AccessCode
	accessCode.Parent = portal

	local place = Instance.new("IntValue")
	place.Name = "PlaceId"
	place.Value = data.PlaceId
	place.Parent = portal

	local counter = Instance.new("IntValue")
	counter.Name = "PocketCounter"
	counter.Value = data.PocketCounter
	counter.Parent = portal

	local creator = Instance.new("IntValue")
	creator.Name = "CreatorId"
	creator.Value = data.CreatorId
	creator.Parent = portal

	local label = portal:FindFirstChild("Label")
	if label and data.PocketName ~= nil then
		local gui = label:FindFirstChild("SurfaceGui")
		if gui then
			local text = gui:FindFirstChild("TextLabel")
			if text then
				text.Text = data.PocketName
			end
		end
	end

	local slight = Instance.new("SurfaceLight")
	slight.Name = "SurfaceLight"
	slight.Range = 9
	slight.Brightness = 1
	slight.Parent = portal.PrimaryPart

	portal.IsOpen.Value = true
	CollectionService:AddTag(portal, "metaportal")	
end

function MetaPortal.KeyForPortal(portal)
	if not portal.PersistId then
		print("[MetaPortal] Pocket has no PersistId")
		return
	end
	
	local persistId = portal.PersistId.Value
	
	local portalKey
	
	if isPocket() then
		-- We are in a pocket
		-- and so the key to look up this pocket portal also needs
		-- to involve the unique identifier of the pocket
		local idValue = workspace:FindFirstChild("PrivateServerKey")
		if not idValue then
			print("[MetaPortal] Failed to initialise pocket portal")
			return
		end

		portalKey = "metapocket/portal/"..idValue.Value.."-"..persistId
	else
		-- In the top level server we just use the PersistId as a key
		portalKey = "metapocket/portal/"..persistId
	end
	
	return portalKey
end

function MetaPortal.InitPocketPortal(portal)
	local DataStore = DataStoreService:GetDataStore(Config.PocketDataStoreTag)
	
	if not portal.PersistId then
		print("[MetaPortal] Pocket has no PersistId")
		return
	end

	if not portal.PrimaryPart then
		print("[MetaPortal] Pocket has no PrimaryPart")
		return
	end
	
	local persistId = portal.PersistId.Value
	local teleportPart = portal.PrimaryPart
	
	local isOpen = Instance.new("BoolValue")
	isOpen.Value = false
	isOpen.Name = "IsOpen"
	isOpen.Parent = portal
	
	-- See if this pocket portal is in the DataStore
	local portalKey = MetaPortal.KeyForPortal(portal)
	
	local success, pocketJSON
	success, pocketJSON = pcall(function()
		return DataStore:GetAsync(portalKey)
	end)
	if not success then
		print("[MetaPortal] GetAsync fail for pocket portal" .. portalKey .. " " .. pocketJSON)
		return
	end
	
	if pocketJSON then
		-- The pocket has been interacted with already
		local pocketData = HTTPService:JSONDecode(pocketJSON)
		MetaPortal.AttachValuesToPocketPortal(portal, pocketData)
	else
		-- This hasn't been opened yet, so create a touch event to open it
		local connection
		
		local db = false -- debounce
		local function onPortalTouch(otherPart)
			if not otherPart then return end
			if not otherPart.Parent then return end

			local humanoid = otherPart.Parent:FindFirstChildWhichIsA("Humanoid")
			if humanoid then
				if not db then
					db = true
					local plr = Players:GetPlayerFromCharacter(otherPart.Parent)
					if plr then	
						-- Check permissions
						if not MetaPortal.HasPocketPermission(plr) then
							print("[MetaPortal] User is not authorised to make pockets")
							wait(0.1)
							db = false
							return
						end
						
						-- Check to see if this player has exceeded their quota of pockets
						local pockets = CollectionService:GetTagged(Config.PocketTag)
						
						local count = 0
						for _, pocket in ipairs(pockets) do
							local creator = pocket:FindFirstChild("CreatorId")
							if creator and creator.Value == plr.UserId then
								count += 1
							end
						end
						
						-- In a pocket the creator can make as many sub-pockets as they wish
						if count >= Config.PocketQuota and not (isPocket() and MetaPortal.PocketData.CreatorId == plr.UserId) then
							print("[MetaPortal] User has reached the pocket quota")
							wait(0.1)
							db = false
							return
						end
						
						CreatePocketEvent:FireClient(plr, portal)
					end
					wait(0.1)
					db = false
				end
			end
		end
		connection = teleportPart.Touched:Connect(onPortalTouch)
		MetaPortal.PocketInitTouchConnections[portal] = connection
	end
end

function MetaPortal.PlayerArrive(plr, data)
	if data == nil then
		print("[MetaPortal] Player arrived with nil TeleportData")
		return
	end
	
	MetaPortal.TeleportData[plr.UserId] = data
	
	if isPocket() and not MetaPortal.PocketInit then
		MetaPortal.InitPocket(data)
	end

	local joinData = plr:GetJoinData()
	if joinData.TeleportData and joinData.TeleportData.pocket then
		local teleportData = joinData.TeleportData
		local pocket = teleportData.pocket
		
		local passThrough = true
		MetaPortal.GotoPocketHandler(plr, pocket, passThrough)
	end
end

return MetaPortal
