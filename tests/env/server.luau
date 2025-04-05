local create_coldnet_inst = require("@tests/utils/create_coldnet_inst")
local env = require("./env")

local server = {}
local metatable = { __index = server }
export type Identity = typeof(setmetatable(
	{} :: {
		instance: typeof(require("@src/")),
	},
	metatable
))

local function constructor(passed_env: env.Identity): Identity
	local self = setmetatable({}, metatable)

	self.instance = create_coldnet_inst()
	local internal = self.instance.__INTERNAL

	internal.run_context = function()
		return "server" :: "server"
	end

	internal.fire_all_clients_func = function(buff)
		for _, client_sig in passed_env.client_signals do
			client_sig:fire(buff)
		end
	end

	internal.fire_client_func = function(client, buff)
		local client_sig = passed_env.client_signals[client]
		if client_sig then
			client_sig:fire(buff)
		end
	end

	internal.connect_server_func = function(callback)
		passed_env.server_signal:connect(callback)
	end

	print("server created")

	return self
end

return {
	new = constructor,
}
