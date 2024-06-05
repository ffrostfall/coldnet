return [==[--# selene: allow(unused_variable)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FRESH_CHANNEL_BUFFER_SIZE = 1024

local unreliableRemoteInstance: UnreliableRemoteEvent = ReplicatedStorage:WaitForChild("COLDNET_UNRELIABLE") :: any
local reliableRemoteInstance: RemoteEvent = ReplicatedStorage:WaitForChild("COLDNET_RELIABLE") :: any
local loadedRemoteInstance: RemoteEvent = ReplicatedStorage:WaitForChild("COLDNET_META") :: any

-- Unreliable
local unreliableChannelBuffer = buffer.create(FRESH_CHANNEL_BUFFER_SIZE)
local unreliableChannelCursor = 0

local function cutUnreliableChannelBuffer()
	local cutBuffer = buffer.create(unreliableChannelCursor)
	buffer.copy(cutBuffer, 0, unreliableChannelBuffer, unreliableChannelCursor)

	return cutBuffer
end

local function allocateUnreliable(bytes: number)
	local outgoingLength = buffer.len(unreliableChannelBuffer)
	if unreliableChannelCursor + bytes < outgoingLength then
		return
	end

	outgoingLength *= 2

	local newBuff = buffer.create(outgoingLength)
	buffer.copy(newBuff, 0, unreliableChannelBuffer)

	unreliableChannelBuffer = newBuff
end

-- Reliable
local reliableChannelBuffer = buffer.create(FRESH_CHANNEL_BUFFER_SIZE)
local reliableChannelCursor = 0

local function cutReliableChannelBuffer()
	local cutBuffer = buffer.create(reliableChannelCursor)
	buffer.copy(cutBuffer, 0, reliableChannelBuffer, reliableChannelCursor)

	return cutBuffer
end

local function allocateReliable(bytes: number)
	local outgoingLength = buffer.len(reliableChannelBuffer)
	if reliableChannelCursor + bytes < outgoingLength then
		return
	end

	outgoingLength *= 2

	local newBuff = buffer.create(outgoingLength)
	buffer.copy(newBuff, 0, reliableChannelBuffer)

	reliableChannelBuffer = newBuff
end
]==]