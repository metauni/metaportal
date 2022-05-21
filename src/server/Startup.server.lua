local ReplicatedStorage = game:GetService("ReplicatedStorage")

do
	-- Move folder/guis around if this is the package version
	local metaPortalCommon = script.Parent:FindFirstChild("MetaPortalCommon")
	if metaPortalCommon then
		if ReplicatedStorage:FindFirstChild("Icon") == nil then
			metaPortalCommon.Packages.Icon.Parent = ReplicatedStorage
		end
		metaPortalCommon.Parent = ReplicatedStorage
	end
	
	local metaPortalPlayer = script.Parent:FindFirstChild("MetaPortalPlayer")
	if metaPortalPlayer then
		metaPortalPlayer.Parent = game:GetService("StarterPlayer").StarterPlayerScripts
	end
	
	local metaPortalGui = script.Parent:FindFirstChild("MetaPortalGui")
	if metaPortalGui then
		local StarterGui = game:GetService("StarterGui")
		-- Gui's need to be top level children of StarterGui in order for
		-- ResetOnSpawn=false to work properly
		for _, guiObject in ipairs(metaPortalGui:GetChildren()) do
			guiObject.Parent = StarterGui
		end
	end
end

local MetaPortal = require(script.Parent.MetaPortal)
MetaPortal.Init()