export type Identity = {
	name: string,
}

local function create(parameters: Identity): Identity
	return parameters
end

return {
	test = create({
		name = "test",
	}),

	test2 = create({
		name = "test2",
	}),
}
