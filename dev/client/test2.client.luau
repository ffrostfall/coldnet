--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local latestet = require(ReplicatedStorage.Packages.coldnet)
local net = require(ReplicatedStorage.shared.net)

ReplicatedStorage:WaitForChild("RemoteEvent")
ReplicatedStorage.RemoteEvent.OnClientEvent:Connect(function() end)

net.test.setClientCallback(function() end)

RunService.Heartbeat:Connect(function()
	latestet.emptyNetworkQueue()
end)
