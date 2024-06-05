local fs = require("@lune/fs")

local clientTemplate = fs.readFile("template/client.luau")
local serverTemplate = fs.readFile("template/server.luau")

fs.writeFile("src/template/client.luau", `return [==[{clientTemplate}]==]`)
fs.writeFile("src/template/server.luau", `return [==[{serverTemplate}]==]`)
