--!strict
--!native
--!optimize 2

--[=[
	Calls the given function and returns the result.
    If the function yields or throws an error, the thread is closed and an error is thrown.
    Regardless of the outcome, the `finally` function is called to clean up any resources.

	@param callback The function to run.
	@param finally Cleanup logic to run before error handling.
	@param ... Arguments to pass to the callback.
	@return ... The results of the callback.
]=]
local function try<TOutput, TInput...>(callback: (TInput...) -> TOutput | nil, finally: (...any) -> ...any | nil, ...: TInput...): TOutput
	local thread = coroutine.create(callback)
	local success, result = coroutine.resume(thread, ...)

	if finally then
		finally()
	end

	-- check whether the thread was yielded.
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)

		local source, line, name = debug.info(callback, "sln")

		error(
			"Yielding is not allowed in atom functions. Consider wrapping this code in a Promise or task.defer instead."
				.. `\nFunction defined at: {source}:{line}`
				.. if name == "" then "" else ` function {name}`
		)
	elseif not success then
		local source, line, name = debug.info(callback, "sln")

		error(
			"An error occurred while running an atom function"
				.. `\nFunction defined at: {source}:{line}`
				.. (if name == "" then "" else ` function {name}`)
				.. `\nError: {result}`
		)
	end

	return result
end

return try
