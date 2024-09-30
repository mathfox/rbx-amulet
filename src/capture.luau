--!strict
--!native
--!optimize 2

--[=[
	Captures all atoms that are read during the function call and returns them along with the result of the function.
    Useful for tracking dependencies.

	@param molecule The function to run.
	@return A tuple containing the captured atoms and the result of the function.
]=]
local function capture<T>(molecule: Molecule<T>): (Set<UnknownAtom>, T)
	if listeners[molecule] then
		return { [molecule] = true }, molecule()
	end

	local dependencies: Set<UnknownAtom> = {}
	capturing[dependencies] = true

	local result = try(molecule, function()
		capturing[dependencies] = nil
	end)

	return dependencies, result
end

return capture
