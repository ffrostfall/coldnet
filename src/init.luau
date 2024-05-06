--!optimize 2
--!native
local FRESH_CHANNEL_BUFFER_SIZE = 1024

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local runContext: "server" | "client" = if RunService:IsServer() then "server" else "client"

--[[
	Buffer channels
]]
type ChannelData = {
	buff: buffer,
	cursor: number,
}

local template: ChannelData = {
	buff = nil :: any,
	cursor = 0,
}

local function blankChannel(): ChannelData
	local freshChannel = table.clone(template)
	freshChannel.buff = buffer.create(FRESH_CHANNEL_BUFFER_SIZE)

	return freshChannel
end

local ref = blankChannel()
local outgoingBuff = ref.buff
local outgoingCursor = ref.cursor

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

-- FOR SOME DAMN REASON HAVING A GROWTH FACTOR OF MATH.ROUND 1.5 MEANS
-- GET THIS RIGHT
-- IDEK WHY BUT SPECULATIVE EXECUTION MATTERS HERE A LOT
-- I GOT A 50% SPEEDUP BY CHANGING IT TO 2 INSTEAD OF math.round(1.5)
-- I GUESS ITS BECAUSE THE CPU HAS LESS WORK TO DO WHEN IT TRIES TO GUESS IT NEEDS TO RUN THIS FUNCTION.
-- im so DONE OAIJDUISADHASUYD GNSAYTf bdzsyt fdxyugf xdtgyf t
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

--[[
	Instances
]]
type Instances = {
	unreliableRemoteInstance: UnreliableRemoteEvent,
	reliableRemoteInstance: RemoteEvent,
	loadedRemoteInstance: RemoteEvent,
	streamFolderInstance: Folder,
}

local function setupInstances(): Instances
	local unreliableRemoteInstance = nil
	local reliableRemoteInstance = nil
	local loadedRemoteInstance = nil
	local streamFolderInstance = nil

	if runContext == "server" then
		unreliableRemoteInstance = Instance.new("UnreliableRemoteEvent")
		reliableRemoteInstance = Instance.new("RemoteEvent")
		loadedRemoteInstance = Instance.new("RemoteEvent")
		streamFolderInstance = Instance.new("Folder")

		unreliableRemoteInstance.Name = "COLDNET_UNRELIABLE"
		unreliableRemoteInstance.Parent = ReplicatedStorage

		reliableRemoteInstance.Name = "COLDNET_RELIABLE"
		reliableRemoteInstance.Parent = ReplicatedStorage

		loadedRemoteInstance.Name = "COLDNET_META"
		loadedRemoteInstance.Parent = ReplicatedStorage

		streamFolderInstance.Name = "COLDNET_STREAMS"
		streamFolderInstance.Parent = ReplicatedStorage
	elseif runContext == "client" then
		unreliableRemoteInstance = ReplicatedStorage:WaitForChild("COLDNET_UNRELIABLE") :: UnreliableRemoteEvent
		reliableRemoteInstance = ReplicatedStorage:WaitForChild("COLDNET_RELIABLE") :: RemoteEvent
		loadedRemoteInstance = ReplicatedStorage:WaitForChild("COLDNET_META") :: RemoteEvent
		streamFolderInstance = ReplicatedStorage:WaitForChild("COLDNET_STREAMS") :: Folder
	end

	return {
		unreliableRemoteInstance = unreliableRemoteInstance,
		reliableRemoteInstance = reliableRemoteInstance,
		loadedRemoteInstance = loadedRemoteInstance,
		streamFolderInstance = streamFolderInstance,
	}
end

--[[
	Threading
]]
local freeThread: thread? = nil

local function execute(callback, buff: buffer, player: Player)
	local threadRef = freeThread
	freeThread = nil
	callback(buff, player)
	freeThread = threadRef
end

local function perpetualExecution()
	while true do
		execute(coroutine.yield())
	end
end

local function recycledSpawn(callback: (buff: buffer, player: Player) -> (), buff: buffer, player: Player)
	if freeThread == nil then
		freeThread = coroutine.create(perpetualExecution)
		task.spawn(freeThread :: thread)
	end

	task.spawn(freeThread :: thread, callback, buff, player)
end

--[[
	Channels
]]
type PlayerChannelSet = {
	[Player]: ChannelData,
}

local globalReliable = blankChannel()
local globalUnreliable = blankChannel()

local reliablePlayerChannels: { [Player]: ChannelData } = (
	setmetatable({}, {
		__mode = "k",
	}) :: any
) :: { [Player]: ChannelData }
local unreliablePlayerChannels: { [Player]: ChannelData } = (
	setmetatable({}, {
		__mode = "k",
	}) :: any
) :: { [Player]: ChannelData }

--[[
	Streams
]]

--[[
	Packets
]]
local callbacks: { [number]: ((buff: buffer, player: Player) -> ()) | ((buff: buffer, player: Player?) -> ()) } = {}
local sizes: { [number]: number? } = {}

local function staticallySizedPacket(packetID: number, size: number)
	sizes[packetID] = size
	local sizeOffset = size + 1

	return function(channel: ChannelData, buff: buffer)
		loadChannel(channel)
		alloc(sizeOffset)

		buffer.writeu8(outgoingBuff, outgoingCursor, packetID)
		buffer.copy(outgoingBuff, outgoingCursor + 1, buff)

		outgoingCursor += sizeOffset

		saveChannel()
	end
end

local function dynamicallySizedPacket(packetID: number)
	return function(channel: ChannelData, buff: buffer)
		local buffLen = buffer.len(buff)

		loadChannel(channel)
		dynalloc(buffLen + 3)

		buffer.writeu8(outgoingBuff, outgoingCursor, packetID)
		outgoingCursor += 1

		buffer.writeu16(outgoingBuff, outgoingCursor, buffLen)
		outgoingCursor += 2

		buffer.copy(outgoingBuff, outgoingCursor, buff)
		outgoingCursor += buffLen

		saveChannel()
	end
end

local function clientToServerMessage(packetID: number, reliabilityType: Reliability, size: number?)
	local globalChannel = if reliabilityType == "reliable" then globalReliable else globalUnreliable

	callbacks[packetID] = function() end
	local packetInterface: (channel: ChannelData, buff: buffer) -> () = (
		if size then staticallySizedPacket(packetID, size) else dynamicallySizedPacket(packetID)
	)

	local function sendServer(buff: buffer)
		packetInterface(globalChannel, buff)
	end

	local function setServerCallback(callback: (buff: buffer, player: Player) -> ())
		callbacks[packetID] = callback
	end

	return {
		sendServer = sendServer,

		setServerCallback = setServerCallback,
	}
end

local function serverToClientMessage(packetID: number, reliabilityType: Reliability, size: number?)
	local globalChannel = if reliabilityType == "reliable" then globalReliable else globalUnreliable
	local channelSet = if reliabilityType == "reliable" then reliablePlayerChannels else unreliablePlayerChannels
	callbacks[packetID] = function() end

	local packetInterface: (channel: ChannelData, buff: buffer) -> () = (
		if size then staticallySizedPacket(packetID, size) else dynamicallySizedPacket(packetID)
	)

	local function sendClient(player: Player, buff: buffer)
		packetInterface((channelSet :: any)[player], buff)
	end

	local function sendAllClients(buff: buffer)
		packetInterface(globalChannel, buff)
	end

	local function setClientCallback(callback: (buff: buffer, player: Player) -> ())
		callbacks[packetID] = callback
	end

	return {
		sendClient = sendClient,
		sendAllClients = sendAllClients,

		setClientCallback = setClientCallback,
	}
end

local function stream(objectSize: number)
	local workingMemory = buffer.create(objectSize)
	local batchBuffers: { buffer } = {}
	local callback = function(_: buffer, _: Player?) end
	local index = 0

	local function start(count: number)
		local totalSize = count * objectSize
		local fragmentCount = math.floor(totalSize / 880)
		local leftoverBytes = totalSize % 880
		index = 0

		for _ = 1, fragmentCount do
			local fragmentBuffer = buffer.create(880)
			table.insert(batchBuffers, fragmentBuffer)
		end

		if leftoverBytes > 0 then
			local leftoverBuffer = buffer.create(leftoverBytes)
			table.insert(batchBuffers, leftoverBuffer)
		end

		return workingMemory
	end

	local function write()
		buffer.copy(batchBuffers[#batchBuffers], objectSize * index, workingMemory)
		index += 1
	end

	local function setCallback(newCallback: (buff: buffer, player: Player?) -> ())
		callback = newCallback
	end

	local function onBatchReceived(buff: buffer, player: Player?)
		local elementCount = math.ceil(buffer.len(buff) / objectSize)
		local workingReceiveMemory = buffer.create(objectSize)

		for i = 1, elementCount do
			buffer.copy(workingReceiveMemory, 0, buff, objectSize * (i - 1), objectSize)

			callback(workingReceiveMemory, player)
		end
	end

	return {
		startBatch = start,
		writeObject = write,
		onBatchReceived = onBatchReceived,
		setCallback = setCallback,

		batchBuffers = batchBuffers,
	}
end

local function clientToServerStream(unreliable: UnreliableRemoteEvent, objectSize: number)
	local streamObject = stream(objectSize)

	local function complete()
		for _, buff in streamObject.batchBuffers do
			unreliable:FireServer(buff)
		end

		table.clear(streamObject.batchBuffers)
	end

	if runContext == "server" then
		unreliable.OnServerEvent:Connect(function(player: Player, buff: buffer)
			streamObject.onBatchReceived(buff, player)
		end)
	end

	return {
		startBatch = streamObject.startBatch,
		write = streamObject.writeObject,
		setCallback = streamObject.setCallback,

		completeBatch = complete,
	}
end

local function serverToClientStream(reliable: RemoteEvent, objectSize: number)
	local streamObject = stream(objectSize)

	local function complete(player: Player)
		for _, buff in streamObject.batchBuffers do
			reliable:FireClient(player, buff)
		end

		table.clear(streamObject.batchBuffers)
	end

	if runContext == "client" then
		reliable.OnClientEvent:Connect(function(buff: buffer)
			streamObject.onBatchReceived(buff, nil)
		end)
	end

	return {
		startBatch = streamObject.startBatch,
		write = streamObject.writeObject,
		setCallback = streamObject.setCallback,

		completeBatch = complete,
	}
end

--[[
	Types
]]
type Reliability = "unreliable" | "reliable"

type ClientToServerMessage = {
	sendServer: (buff: buffer) -> (),
	setServerCallback: (callback: (buff: buffer, player: Player) -> ()) -> (),
}

type ServerToClientMessage = {
	sendClient: (player: Player, buff: buffer) -> (),
	sendAllClients: (buff: buffer) -> (),

	setClientCallback: (callback: (buff: buffer) -> ()) -> (),
}

type Request = {
	onClientRequest: (callback: (buff: buffer, player: Player) -> buffer) -> (),
	request: (buff: buffer) -> buffer,
}

type Stream = {
	startBatch: (count: number) -> buffer,
	write: () -> (),
	setCallback: (callback: (buff: buffer, player: Player?) -> ()) -> (),

	completeBatch: () -> (),
}

type ClientToServerParams = {
	direction: "client -> server",
	reliability: Reliability,
	size: number?,
}

type ServerToClientParams = {
	direction: "server -> client",
	reliability: Reliability,
	size: number?,
}

type ClientToServerStreamParams = {
	direction: "client -> server",
	elementSize: number,
}

type ServerToClientStreamParams = {
	direction: "server -> client",
	elementSize: number,
}

type coldnetAPI = {
	namespace: <T>(parameter: T & { [string]: ClientToServerMessage | ServerToClientMessage | Request }) -> T,
	message: ((params: ServerToClientParams) -> ServerToClientMessage)
		& ((params: ClientToServerParams) -> ClientToServerMessage),
	request: ({
		requestSize: number?,
		replySize: number?,
	}?) -> Request,
	stream: ((params: ServerToClientStreamParams) -> Stream) & ((params: ClientToServerStreamParams) -> Stream),

	emptyNetworkQueue: () -> (),
}

--[[
	Instance fetching
]]
local instanceSingleton = nil
local function getInstances(): Instances
	if not instanceSingleton then
		instanceSingleton = setupInstances()
		return instanceSingleton
	end

	return instanceSingleton
end

--[[
	Outgoing
]]
local function clientEmptyQueue()
	local instances = getInstances()

	local dumpedReliable = dumpChannel(globalReliable)
	local dumpedUnreliable = dumpChannel(globalUnreliable)

	if dumpedReliable then
		instances.reliableRemoteInstance:FireServer(dumpedReliable)
	end

	if dumpedUnreliable then
		instances.unreliableRemoteInstance:FireServer(dumpedUnreliable)
	end
end

local function serverEmptyQueue()
	local instances = getInstances()

	local dumpedGlobalReliable = dumpChannel(globalReliable)
	local dumpedGlobalUnreliable = dumpChannel(globalUnreliable)

	if dumpedGlobalReliable then
		instances.reliableRemoteInstance:FireAllClients(dumpedGlobalReliable)
	end

	if dumpedGlobalUnreliable then
		instances.unreliableRemoteInstance:FireAllClients(dumpedGlobalUnreliable)
	end

	for player, channel in reliablePlayerChannels do
		local dumpedReliable = dumpChannel(channel)

		if dumpedReliable then
			instances.reliableRemoteInstance:FireClient(player, dumpedReliable)
		end
	end

	for player, channel in unreliablePlayerChannels do
		local dumpedUnreliable = dumpChannel(channel)

		if dumpedUnreliable then
			instances.unreliableRemoteInstance:FireClient(player, dumpedUnreliable)
		end
	end
end

local function emptyNetworkQueue()
	if runContext == "client" then
		clientEmptyQueue()
	elseif runContext == "server" then
		serverEmptyQueue()
	end
end

--[[
	Incoming
]]
for i = 0, 255 do
	callbacks[i] = function() end
end

local function handleBuffer(incomingBuff: buffer, player: Player?)
	local cursor = 0
	local incomingBuffLen = buffer.len(incomingBuff)

	debug.profilebegin("receiving")
	while cursor < incomingBuffLen do
		local packetID = buffer.readu8(incomingBuff, cursor)
		local callback = callbacks[packetID]
		local packetSize = sizes[packetID]

		if packetSize then
			local freshBuffer = buffer.create(packetSize)
			buffer.copy(freshBuffer, 0, incomingBuff, cursor + 1, packetSize)

			recycledSpawn(callback, freshBuffer, player :: Player)

			cursor += packetSize + 1
		else
			local bufferSize = buffer.readu16(incomingBuff, cursor + 1)
			local freshBuffer = buffer.create(bufferSize)
			buffer.copy(freshBuffer, 0, incomingBuff, cursor + 3, bufferSize)

			recycledSpawn(callback, freshBuffer, player :: Player)

			cursor += bufferSize + 3
		end
	end
	debug.profileend()
end

local function clientLoop(event: RBXScriptSignal)
	while true do
		handleBuffer(event:Wait())
	end
end

local function serverLoop(event: RBXScriptSignal)
	while true do
		local player, incomingBuff = event:Wait()

		handleBuffer(incomingBuff, player)
	end
end

--[[
	Startup
]]
local function clientStart()
	local instances = getInstances()

	task.spawn(clientLoop, instances.unreliableRemoteInstance.OnClientEvent)
	task.spawn(clientLoop, instances.reliableRemoteInstance.OnClientEvent)

	instances.loadedRemoteInstance:FireServer()
end

local function playerAdded(player: Player)
	reliablePlayerChannels[player] = blankChannel()
	unreliablePlayerChannels[player] = blankChannel()
end

local function serverStart()
	local instances = getInstances()

	for _, player in Players:GetPlayers() do
		playerAdded(player)
	end

	Players.PlayerAdded:Connect(playerAdded)

	task.spawn(serverLoop, instances.unreliableRemoteInstance.OnServerEvent)
	task.spawn(serverLoop, instances.reliableRemoteInstance.OnServerEvent)
end

local function init()
	if runContext == "server" then
		serverStart()
	else
		clientStart()
	end
end

init()

--[[
	Public API
]]

local function namespace(data: {
	[string]: () -> any,
})
	local netArray = {}
	for key in data do
		table.insert(netArray, key)
	end
	table.sort(netArray)

	local createdNamespace: { [string]: any } = {}
	for packetID, key in netArray do
		local netObjectParams = data[key]()

		if netObjectParams.kind == "stream" then
			if netObjectParams.direction == "client -> server" then
				createdNamespace[key] =
					clientToServerStream(getInstances().unreliableRemoteInstance, netObjectParams.elementSize)
			elseif netObjectParams.direction == "server -> client" then
				createdNamespace[key] =
					serverToClientStream(getInstances().reliableRemoteInstance, netObjectParams.elementSize)
			end

			continue
		end

		if netObjectParams.direction == "client -> server" then
			createdNamespace[key] = clientToServerMessage(packetID, netObjectParams.reliability, netObjectParams.size)
		elseif netObjectParams.direction == "server -> client" then
			createdNamespace[key] = serverToClientMessage(packetID, netObjectParams.reliability, netObjectParams.size)
		end
	end

	return createdNamespace
end

local function message(netParams: ServerToClientParams | ClientToServerParams)
	(netParams :: any).kind = "message"

	return function()
		return netParams
	end
end

local function stream(netParams)
	(netParams :: any).kind = "stream"

	return function()
		return netParams
	end
end

return (
	table.freeze({
		namespace = namespace,
		message = message,

		emptyNetworkQueue = emptyNetworkQueue,
	}) :: any
) :: coldnetAPI
