local args = {...}
local input = args[1] or "build.rbxlx"
local output = args[2] or "metaportal.rbxmx"

local game = remodel.readPlaceFile(input)

local portalServer = game.ServerScriptService.metaorb
local portalPlayer = game.StarterPlayer.StarterPlayerScripts.OrbPlayer
local portalCommon = game.ReplicatedStorage.OrbCommon

portalPlayer.Parent = portalServer
portalCommon.Parent = portalServer

remodel.writeModelFile(portalServer, output)