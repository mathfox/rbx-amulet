--[=[
	Creates a new atom with the given state.

	@param state The initial state.
	@param options Optional configuration.
	@return A new atom.
]=]
local function atom<TState>(state: TState, options: AtomOptions<TState> | nil): Atom<T>
	local equals = if options then options.equals else nil

	local function atom(...): T
		if select("#", ...) == 0 then
			for set in capturing do
				set[atom] = true
			end

			return state
		end

		-- Here we are truncating the `...` varargs to just one value.
		-- In this case we assume that this one value is atom mutator.
		local nextState = peek(..., state)

		if state ~= nextState and not (equals and equals(state, nextState)) then
			state = nextState
			notify(atom)
		end

		return state
	end

	listeners[atom] = setmetatable({}, WEAK_VALUES_METATABLE)

	return atom
end

return atom
