local coldnet = require("@src/")
local create_coldnet_inst = require("@tests/utils/create_coldnet_inst")
local env = require("./env")
local signal = require("@vendor/luausignal")

local client = {}
local metatable = { __index = client }
export type Identity = typeof(setmetatable(
	{} :: {
		remote_signal: signal.Identity<buffer>,
		symbol: coldnet.Client,

		instance: typeof(coldnet),
	},
	metatable
))

local function constructor(passed_env: env.Identity): Identity
	local self = setmetatable({}, metatable)

	self.symbol = {
		__T = "Client",
	}

	self.remote_signal = signal()
	passed_env.client_signals[self.symbol] = self.remote_signal

	self.instance = create_coldnet_inst()
	local internal = self.instance.__INTERNAL

	internal.connect_client_func = function(listener)
		self.remote_signal:connect(listener)
	end

	internal.run_context = function()
		return "client" :: "client"
	end

	internal.fire_server_func = function(buff)
		passed_env.server_signal:fire(self.symbol, buff)
	end

	print("client created")

	return self
end

return {
	new = constructor,
}
