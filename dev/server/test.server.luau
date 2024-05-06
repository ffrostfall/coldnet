--!native
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local latestet = require(ReplicatedStorage.Packages.coldnet)
local net = require(ReplicatedStorage.shared.net)

local buff = buffer.create(8)

RunService.Heartbeat:Connect(function()
	local player = Players:GetPlayers()[1]
	if not player then
		return
	end

	debug.profilebegin("sendServer")
	for _ = 1, 10000 do
		ReplicatedStorage.RemoteEvent:FireAllClients(buff)
	end
	--latestet.emptyNetworkQueue()
	debug.profileend()
end)
