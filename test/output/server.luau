--# selene: allow(unused_variable)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FRESH_CHANNEL_BUFFER_SIZE = 1024
local TEMPLATE_CHANNEL: ChannelData = {
	buff = nil :: any,
	cursor = 0,
}

type ChannelData = {
	buff: buffer,
	cursor: number,
}

local ref: ChannelData = {
	buff = buffer.create(1),
	cursor = 0,
}
local outgoingBuff: buffer = ref.buff
local outgoingCursor: number = ref.cursor
local playerChannels: {
	[Player]: {
		reliable: ChannelData,
		unreliable: ChannelData,
	},
} = {}
local globalReliable: ChannelData
local globalUnreliable: ChannelData

local function blankChannel(): ChannelData
	local freshChannel = table.clone(TEMPLATE_CHANNEL)
	freshChannel.buff = buffer.create(FRESH_CHANNEL_BUFFER_SIZE)

	return freshChannel
end

globalReliable = blankChannel()
globalUnreliable = blankChannel()

local function loadChannel(channel: ChannelData)
	if ref == channel then
		return
	end

	ref = channel
	outgoingBuff = channel.buff
	outgoingCursor = channel.cursor
end

local function saveChannel()
	ref.cursor = outgoingCursor
	ref.buff = outgoingBuff
end

local function dumpChannel(channel: ChannelData): buffer?
	local cursor = channel.cursor
	if cursor == 0 then
		return nil
	end

	local dumpBuffer = buffer.create(cursor)

	buffer.copy(dumpBuffer, 0, channel.buff, 0, cursor)

	-- Reset the cursor to zero to effectively clear it
	channel.cursor = 0

	if channel == ref then
		outgoingCursor = 0
	end

	return dumpBuffer
end

local function alloc(bytes: number)
	local outgoingLength = buffer.len(outgoingBuff)
	if outgoingCursor + bytes < outgoingLength then
		return
	end

	outgoingLength *= 2

	local newBuff = buffer.create(outgoingLength)
	buffer.copy(newBuff, 0, outgoingBuff)

	outgoingBuff = newBuff
	return
end

local function dynalloc(bytes: number)
	local outgoingLength = buffer.len(outgoingBuff)
	if outgoingCursor + bytes < outgoingLength then
		return
	end

	-- resize until we can fit the bytes
	while outgoingCursor + bytes > outgoingLength do
		outgoingLength *= 2
	end

	local newBuff = buffer.create(outgoingLength)
	buffer.copy(newBuff, 0, outgoingBuff)

	outgoingBuff = newBuff
	return
end

local function onPlayerAdded(player: Player)
	if not player:IsDescendantOf(game) then
		return
	end

	playerChannels[player] = {
		reliable = blankChannel(),
		unreliable = blankChannel(),
	}
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	playerChannels[player] = nil
end)

local unreliableRemoteInstance = Instance.new("UnreliableRemoteEvent")
local reliableRemoteInstance = Instance.new("RemoteEvent")
local loadedRemoteInstance = Instance.new("RemoteEvent")

unreliableRemoteInstance.Name = "COLDNET_UNRELIABLE"
unreliableRemoteInstance.Parent = ReplicatedStorage

reliableRemoteInstance.Name = "COLDNET_RELIABLE"
reliableRemoteInstance.Parent = ReplicatedStorage

loadedRemoteInstance.Name = "COLDNET_META"
loadedRemoteInstance.Parent = ReplicatedStorage

local function send()
	local dumpedGlobalReliable = dumpChannel(globalReliable)
	local dumpedGlobalUnreliable = dumpChannel(globalUnreliable)

	if dumpedGlobalReliable then
		reliableRemoteInstance:FireAllClients(dumpedGlobalReliable)
	end

	if dumpedGlobalUnreliable then
		unreliableRemoteInstance:FireAllClients(dumpedGlobalUnreliable)
	end

	for player, channels in playerChannels do
		local dumpedReliable = dumpChannel(channels.reliable)
		local dumpedUnreliable = dumpChannel(channels.unreliable)

		if dumpedUnreliable then
			unreliableRemoteInstance:FireClient(player, dumpedUnreliable)
		end

		if dumpedReliable then
			reliableRemoteInstance:FireClient(player, dumpedReliable)
		end
	end
end

