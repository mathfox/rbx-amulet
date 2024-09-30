--[=[
	Subscribes to changes in the given atom or molecule.
    The callback is called with the current state and the previous state immediately after a change occurs.

	@param molecule The atom or molecule to subscribe to.
	@param callback The function to call when the state changes.
	@return A function that unsubscribes the callback.
]=]
local function subscribe<T>(molecule: Molecule<T>, callback: (state: T, prev: T) -> ()): Procedure
	local dependencies, state = capture(molecule)
	local disconnected = false

	local function listener()
		local prevState = state

		disconnect(dependencies, listener)
		dependencies, state = capture(molecule)

		if not disconnected then
			connect(dependencies, listener)
		end

		if state ~= prevState then
			callback(state, prevState)
		end
	end

	connect(dependencies, listener)

	return function()
		if not disconnected then
			disconnected = true

			disconnect(dependencies, listener)
		end
	end
end

return subscribe
