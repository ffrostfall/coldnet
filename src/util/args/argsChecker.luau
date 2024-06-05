local argsParser = require("argsParser")
local process = require("@lune/process")

type expectedOption = {
	requiresValue: boolean,
	alias: string?,
	full: string,
}

type expectedArgument = {
	name: string,
	required: boolean,
	position: number,
}

local function makeExpectedOption(requiresValue: boolean, full: string, alias: string?): expectedOption
	return {
		requiresValue = requiresValue,
		alias = alias,
		full = full,
	}
end

local function makeExpectedArgument(name: string, position: number, required: boolean?): expectedArgument
	return {
		name = name,
		required = required or false,
		position = position,
	}
end

return function()
	local expectedArguments: { [number]: expectedArgument } = {}
	local aliasMap: { [string]: expectedOption } = {}
	local optionNameMap: { [string]: expectedOption } = {}

	local builder
	builder = {}

	function builder.argument(position: number, name: string, required: boolean?)
		expectedArguments[position] = makeExpectedArgument(name, position, required)

		return builder
	end

	function builder.option(optionName: string, requiresValue: boolean, alias: string?)
		optionNameMap[optionName] = makeExpectedOption(requiresValue, optionName, alias)

		if alias then
			aliasMap[alias] = optionNameMap[optionName]
		end

		return builder
	end

	function builder.args(args: string | { string }): { options: { [string]: any }, arguments: { [number]: string } }
		local input = if typeof(args) == "table" then table.concat(args, " ") else args

		local result = argsParser(input)
		local options = {}
		local arguments = {}

		for key, value in result.options do
			local option = optionNameMap[key] or aliasMap[key]
			if not option then
				print(`unknown option {key}`)
				return process.exit(1)
			end

			if option.requiresValue and value == "" then
				print(`option {key} requires a value`)
				return process.exit(1)
			end

			options[option.full] = value
		end

		for _, value in expectedArguments do
			arguments[value.position] = result.arguments[value.position]
		end

		return {
			options = options,
			arguments = arguments,
		}
	end

	return builder
end
