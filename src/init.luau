--[[
	Runtime dependent
]]
export type Client = {
	__T: "Client",
}

local __internals: {
		run_context: () -> ("server" | "client"),
		fire_all_clients_func: (buff: buffer) -> (),
		fire_client_func: (client: Client, buff: buffer) -> (),
		fire_server_func: (buff: buffer) -> (),
		
		connect_server_func: (callback: (client: Client, buff: buffer) -> ()) -> (),
		connect_client_func: (callback: (buff: buffer) -> ()) -> ()
} = {
	run_context = function()
		return "client" :: "client"
	end,
	
	fire_all_clients_func = function(data: any): ()
		print("Fire all clients: ", data)
	end,
	
	fire_client_func = function(player: Client, data: any): ()
		print("Fire client: ", player, data)
	end,
	
	fire_server_func = function(data: any): ()
		print("Fire server: ", data)
	end,
	
	connect_server_func = function(callback: (client: Client, data: any) -> ()): ()
		print("Connect server: ", callback)
	end,
	
	connect_client_func = function(callback: (data: any) -> ()): ()
		print("Connect client: ", callback)
	end,
}

--[[
	Buffer manipulation
]]

local buff = buffer.create(1024)
local cursor = 0

local function cut_buffer(): buffer
	local sliced_buff = buffer.create(cursor)

	buffer.copy(sliced_buff, 0, buff, 0, cursor)

	return sliced_buff
end

local function reset_cursor()
	cursor = 0
end

--[[
	Writers / Readers
]]

local function write_u8(data: number): ()
	buffer.writeu8(buff, cursor, data)
end

local function write_bool(data: boolean): ()
	buffer.writeu8(buff, cursor, if data then 1 else 0)
end

local function read_u8(): number
	return buffer.readu8(buff, cursor)
end

local function read_bool(): boolean
	return buffer.readu8(buff, cursor) == 1
end

--[[
	Remarks / Internal data
]]
type InternalRemarks = {
	max_server_buff_size: number,
	max_client_buff_size: number,
}

local finalized = false
local remarks: InternalRemarks = {
	max_server_buff_size = 0,
	max_client_buff_size = 0,
}

local function apply_remarks(new_remarks: InternalRemarks, context: "server" | "client"): ()
	remarks = new_remarks
	
	if context == "server" then
		buff = buffer.create(new_remarks.max_server_buff_size)
	elseif context == "client" then
		buff = buffer.create(new_remarks.max_client_buff_size)
	end
	
	finalized = true
end

--[[
	Definitions
]]
local defs = {
	schema = {},
}

-- Data type definitions

type Reader<T> = (b: buffer) -> T
type Writer<T> = (data: T) -> ()

export type DataType<T> = {
	__T: T,
	_ACCUMULATED_SIZE: number,

	write: (data: T) -> (),
	read: () -> T,
}

function defs.schema.u8(): DataType<number>
	return {
		__T = 0,
		_ACCUMULATED_SIZE = 1,

		write = function(data: number)
			cursor += 1
			write_u8(data)
		end,

		read = function(): number
			cursor += 1
			return (read_u8())
		end,
	}
end

function defs.schema.bool(): DataType<boolean>
	return {
		__T = false,
		_ACCUMULATED_SIZE = 1,

		write = function(data: boolean)
			write_bool(data)
			cursor += 1
		end,

		read = function(): boolean
			cursor += 1
			return (read_bool())
		end,
	}
end

function defs.schema.arr<T>(data_type: DataType<T>, max_size: number): DataType<{ T }>
	local member_write = data_type.write
	local member_read = data_type.read

	local arr_def = {
		__T = { data_type.__T },
		
		-- Length encoding
		_ACCUMULATED_SIZE = 1 + (data_type._ACCUMULATED_SIZE * max_size),
	}
	
	function arr_def.write(data: { T })
		local size = #data
		if size > max_size then
			error("Array size exceeds maximum limit")
		end
		
		write_u8(size)
		
		for i = 1, size do
			member_write(data[i])
		end
	end
	
	function arr_def.read(): { T }
		local size = read_u8()
		local data = {}
		
		for i = 1, size do
			data[i] = member_read()
		end
		
		return data
	end
	
	return arr_def :: DataType<{ T }>
end

-- Event definitions
export type EventDefinition<T> = {
	schema: DataType<T>,

	max_per_frame: number,
	direction: "server -> client" | "client -> server"
}

--[[
	Data type analysis
]]
export type EventAnalysis = {
	max_size: number,
}

local function analyze_event<T>(event: EventDefinition<T>)
	return event.max_per_frame * event.schema._ACCUMULATED_SIZE
end

--[[
	Finalize definitions
]]

type function finalize_defs(definitions)
	assert(definitions.tag == "table", "Expected a table")
	local events = definitions:properties()
	
	local client_events_api = {}
	local server_events_api = {}
	
	for key, event_def in events do
		local direction = event_def.read:readproperty(types.singleton("direction")):value()
		local schema = event_def.read:readproperty(types.singleton("schema"))
		local schema_type = schema:readproperty(types.singleton("__T"))
		
		if direction == "server -> client" then
			client_events_api[key] = types.newtable({
				[types.singleton("on")] = types.newfunction({head = { types.newfunction({ head = {schema_type} }) }}),
			})
			server_events_api[key] = types.newtable({
				[types.singleton("fire")] = types.newfunction({head = { types.number, schema_type }}),
				[types.singleton("fire_all")] = types.newfunction({head = { schema_type }}),
			})
		elseif direction == "client -> server" then
			client_events_api[key] = types.newtable({
				[types.singleton("fire")] = types.newfunction({head = { types.number, schema_type }}),
			})
			server_events_api[key] = types.newtable({
				[types.singleton("on")] = types.newfunction({head = { types.newfunction({ head = {types.number, schema_type} }) }}),
			})
		end
	end
	
	return types.newtable({
		[types.singleton("client")] = types.newtable(client_events_api),
		[types.singleton("server")] = types.newtable(server_events_api),
	})
end

local function finalize_defs<T>(definitions: T): finalize_defs<T>
	local internal_remarks: InternalRemarks = {
		max_server_buff_size = 0,
		max_client_buff_size = 0,
	}
	local returned_api = {
		client = {},
		server = {}
	}
	
	for event_name, event_def in definitions :: { [string]: EventDefinition<any> } do
		local built_api_object = {
			on = function() end,
		}
		
		-- Analyze max size and increase buffer size accordingly
		local max_size = analyze_event(event_def)
		if event_def.direction == "client -> server" then
			internal_remarks.max_client_buff_size += max_size
		elseif event_def.direction == "server -> client" then
			internal_remarks.max_server_buff_size += max_size
		end
	end
	
	
	
	return returned_api :: any
end

local function server_to_client(): "server -> client"
	return "server -> client"
end

local function client_to_server(): "client -> server"
	return "client -> server"
end

local t = finalize_defs({
	abcd = {
		schema = defs.schema.u8(),
		max_per_frame = 10,
		direction = server_to_client(),
	},
	bacd = {
		schema = defs.schema.arr(defs.schema.u8(), 10),
		max_per_frame = 10,
		direction = client_to_server(),
	}
})

return {
	__INTERNAL = __internals,
}