local fs = require("@lute/fs")
local luau = require("@lute/luau")

local cached_inst_creator: (() -> any)? = nil

local function create_coldnet_vm(): typeof(require("@src/"))
	if cached_inst_creator then
		return (cached_inst_creator :: () -> any)()
	end

	local coldnet_src = fs.readasync("src/init.luau")
	local coldnet_bytecode = luau.compile(coldnet_src, {
		debugLevel = 2,
		optimizationLevel = 2,
	})
	local new_inst = luau.load(coldnet_bytecode)

	cached_inst_creator = new_inst
	return new_inst() :: any
end

return create_coldnet_vm
