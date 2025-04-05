type LuauApi = {
	compile: (
		source: string,
		compile_options: {
			optimization_level: number?,
			debug_level: number?,
			coverage_level: number?,
		}?
	) -> CompilerResult,

	load: (compiler_result: CompilerResult) -> () -> any,
}

return (require("@lute/luau") :: any) :: LuauApi
