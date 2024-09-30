--!strict
--!native
--!optimize 2

--[=[
	Creates a read-only atom that derives its state from one or more atoms.
	Used to avoid unnecessary recomputations if multiple listeners depend on the same molecule.

	@param molecule The function that produces the state.
	@param options Optional configuration.
	@return A new read-only atom.
]=]
local function computed<T>(molecule: Molecule<T>, options: AtomOptions<T>?): Molecule<T>
	local dependencies, state = capture(molecule)
	local computedAtom = atom(state, options)
	local computedRef = setmetatable({ current = computedAtom }, WEAK_VALUES_METATABLE)

	local function listener()
		local computedAtom = computedRef.current

		if computedAtom then
			disconnect(dependencies, listener)
			dependencies, state = capture(molecule)
			connect(dependencies, listener, computedAtom)
			computedAtom(state)
		end
	end

	connect(dependencies, listener, computedAtom)

	return computedAtom
end

return computed
