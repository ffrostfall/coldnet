local clientTemplate = require("@template/client")
local fs = require("@lune/fs")
local serverTemplate = require("@template/server")

type PacketDefinition = {
	id: number,
	data: any,
}

type Configuration = {}

local files: {
	server: { string },
	client: { string },
} = {
	server = {},
	client = {},
}

local function writeClient(text: string)
	table.insert(files.client, text)
end

local function writeServer(text: string)
	table.insert(files.server, text)
end

local function writeShared(text: string)
	writeClient(text)
	writeServer(text)
end

local function finalize(lines: { string })
	return table.concat(lines, "\n")
end

local function codegen(_definitions: { PacketDefinition }, _config: Configuration)
	writeClient(clientTemplate)
	writeServer(serverTemplate)

	local clientSource = finalize(files.client)
	local serverSource = finalize(files.server)

	fs.writeFile("test/output/client.luau", clientSource)
	fs.writeFile("test/output/server.luau", serverSource)
end

codegen()

return codegen
