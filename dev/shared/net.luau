local latestet = require(script.Parent.Parent.Packages.coldnet)
return latestet.namespace({
	["test"] = latestet.message({
		direction = "server -> client",
		reliability = "reliable",
		size = 8,
	}),
})
