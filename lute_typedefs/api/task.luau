type TaskApi = {
	defer: <A..., R...>(f: thread | ((A...) -> R...), A...) -> thread,
	wait: (duration: number?) -> number,
}

return (require("@lute/task") :: any) :: TaskApi
