local task = require("@vendor/task")
local test_environment = require("@tests/test_environment")

local test = test_environment.new()

local clientA = test:add_client()
local clientB = test:add_client()

test:execute_for_client(clientA, function(coldnet)
	while true do
		print("client A frame")

		task.wait(1 / 60)
	end
end)

test:execute_for_client(clientB, function(coldnet)
	while true do
		print("client B frame")

		task.wait(1 / 60)
	end
end)

test:execute_for_server(function(coldnet)
	while true do
		print("server frame")

		task.wait(1 / 60)
	end
end)

task.start()
