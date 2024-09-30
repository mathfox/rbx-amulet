--!strict
--!native
--!optimize 2

local types = require(script.Parent.types)

--[=[
	Runs the given callback immediately and whenever any atom it depends on changes.
    Returns a cleanup function that unsubscribes the callback.

	@param callback The function to run.
	@return A function that unsubscribes the callback.
]=]
local function effect(callback: () -> types.CleanupCallback | nil): types.CleanupCallback
	local dependencies, cleanup = capture(callback)
	local disconnected = false

	local function listener()
		if cleanup then
			cleanup()
		end

		disconnect(dependencies, listener)
		dependencies, cleanup = capture(callback)

		if not disconnected then
			connect(dependencies, listener)
		end
	end

	connect(dependencies, listener)

	return function()
		if not disconnected then
			disconnected = true
			disconnect(dependencies, listener)

			if cleanup then
				cleanup()
			end
		end
	end
end

return effect
