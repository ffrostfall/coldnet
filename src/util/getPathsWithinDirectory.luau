local fs = require("@lune/fs")

local function read(currentDir: string, arrayRef: { string })
	local contents = fs.readDir(currentDir)
	if not contents then
		return
	end

	for _, filePath in contents do
		local path = currentDir .. "/" .. filePath

		if fs.isDir(path) then
			read(path, arrayRef)
		else
			table.insert(arrayRef, path)
		end
	end
end

return function(directory: string)
	local paths = {}
	read(directory, paths)
	return paths
end
