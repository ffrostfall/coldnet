local client = require("@tests/env/client")
local coldnet = require("@src/")
local env = require("@tests/env/env")
local server = require("@tests/env/server")
local task = require("@vendor/task")

local test_environment = {}
local metatable = { __index = test_environment }
export type Identity = typeof(setmetatable(
	{} :: {
		env: env.Identity,
		server: server.Identity,
		clients: { [coldnet.Client]: client.Identity },
	},
	metatable
))

local function constructor(): Identity
	local self = setmetatable({
		env = env(),
		server = server.new(env()),
		clients = {},
	}, metatable)

	return self
end

function test_environment.execute_for_server(self: Identity, func: (typeof(coldnet)) -> ())
	task.spawn(func, self.server.instance)
end

function test_environment.execute_for_client(self: Identity, target: client.Identity, func: (typeof(coldnet)) -> ())
	task.spawn(func, target.instance)
end

function test_environment.add_client(self: Identity): client.Identity
	local new_client = client.new(self.env)
	self.clients[new_client.symbol] = new_client

	return new_client
end

return {
	new = constructor,
}
