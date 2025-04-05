type FsApi = {
	readasync: (path: string) -> string,
}

return (require("@lute/fs") :: any) :: FsApi
