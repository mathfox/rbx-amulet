export type AtomProceduresMap = WeakValues<Procedure, unknown>

--[=[
    A map from `atom` to `ProceduresMap`.
    When there is no more reference to the `atom`, the entry is this map is gced.

    The `ProceduresMap` is a map from `Procedure` to any value.
]=]
local listeners: WeakKeys<UnknownAtom, AtomProceduresMap> = setmetatable({}, { __mode = "k" } :: WeakKeysMetatable)

local capturing: Set<Set<UnknownAtom>> = {}
local batched: Set<Procedure> = {}

local batching = false

--[=[

	Returns whether the given value is an atom.

	@param value The value to check.
	@return `true` if the value is an atom, otherwise `false`.
]=]
local function isAtom(value: unknown): boolean
	return not not (value and listeners[value])
end

--[=[
	Notifies all subscribers of the given atom that the state has changed.

	@param atom The atom to notify.
]=]
local function notify(atom: UnknownAtom)
	if batching then
		for listener in (listeners[atom] :: any) :: { [Procedure]: unknown } do
			batched[listener] = true
		end

		return
	end

	for listener in (table.clone(listeners[atom]) :: any) :: { [Procedure]: unknown } do
		try(listener)
	end
end

--[=[
	Returns the result of the function without subscribing to changes.
    If a non-function value is provided, it is returned as is.

	@param molecule The atom or molecule to get the state of.
	@param args Arguments to pass to the molecule.
	@return The current state.
]=]
local function peek<T, U...>(callback: ((U...) -> T) | T, ...: U...): T
	if type(callback) ~= "function" then
		return callback
	end

	-- check whether it's empty
	if not next(capturing) then
		return callback(...)
	end

	local snapshot = table.clone(capturing)

	table.clear(capturing)

	local result = try(callback, function()
		for set in snapshot do
			capturing[set] = true
		end
	end, ...)

	return result
end
