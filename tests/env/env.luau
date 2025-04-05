local coldnet = require("@src/")
local signal = require("@vendor/luausignal")

export type Identity = {
	client_signals: { [coldnet.Client]: signal.Identity<buffer> },
	server_signal: signal.Identity<coldnet.Client, buffer>,
}

local function env(): Identity
	local new_env = {}

	new_env.client_signals = {}
	new_env.server_signal = signal()

	return new_env
end

return env
