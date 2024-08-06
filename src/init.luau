--!strict
--!native
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WEAK_VALUES_METATABLE = { __mode = "v" } :: WeakValuesMetatable

local ReactInstance: ModuleScript
local React: any | nil

do
	local temp = script.Parent
	assert(temp)

	temp = temp.Parent
	assert(temp)

	temp = temp:FindFirstChild("ReactLua")
	assert(temp)

	temp = temp:FindFirstChild("React")
	assert(temp and temp:IsA("ModuleScript"))

	ReactInstance = temp
end

local function requireReact(): any
	if not React then
		React = require(ReactInstance) :: any
	end
	return React
end

export type Set<T> = { [T]: true }

export type WeakKeysMetatable = {
	__mode: "k",
}

export type WeakValuesMetatable = {
	__mode: "v",
}

export type WeakKeys<K, V> = typeof(setmetatable({} :: { [K]: V }, (nil :: any) :: WeakKeysMetatable))
export type WeakValues<K, V> = typeof(setmetatable({} :: { [K]: V }, (nil :: any) :: WeakValuesMetatable))

--[=[
	A primitive state container that can be read from and written to. When the
	state changes, all subscribers are notified.

	@param state The next state or a function that produces the next state.
	@return The current state, if no arguments are provided.
]=]
export type Atom<T> = (() -> T) & (state: T | (T) -> T) -> T

--[=[
	A function that depends on one or more atoms and produces a state.
    Can be used to derive state from atoms.

	@template State The type of the state.
	@return The current state.
]=]
export type Molecule<T> = () -> T

--[=[
	Optional configuration for creating an atom.
]=]
export type AtomOptions<T> = {
	--[=[
		A function that determines whether the state has changed.
        By default, a strict equality check (`===`) is used.
	]=]
	equals: (prev: T, next: T) -> boolean,
}

--[=[
	A payload that can be sent from the server to the client to synchronize
	state between the two.
]=]
export type SyncPayload = {
	type: "patch" | "init",
	data: { [any]: any },
}

export type UnknownAtom = Atom<unknown>

-- A function that does not accept anything and does not return anything.
export type Procedure = () -> ()

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

--local function packResult(success: boolean, ...): (boolean, number, { unknown })
--	return success, select("#", ...), { ... }
--end

--[=[
	Calls the given function and returns the result.
    If the function yields or throws an error, the thread is closed and an error is thrown.
    Regardless of the outcome, the `finally` function is called to clean up any resources.

	@param callback The function to run.
	@param finally Cleanup logic to run before error handling.
	@param ... Arguments to pass to the callback.
	@return ... The results of the callback.
]=]
local function try<T, U...>(callback: (U...) -> T | nil, finally: Procedure | nil, ...: U...): T
	local thread = coroutine.create(callback)
	--local success, resultCount, result = packResult(coroutine.resume(thread, ...))
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

	-- TODO: Luau does not allow { unknown } type to be unpacked.
	--return unpack(result :: { any }, 1, resultCount)

	return result
end

--[=[
	Returns whether the given value is an atom.

	@param value The value to check.
	@return `true` if the value is an atom, otherwise `false`.
]=]
local function isAtom(value: unknown): boolean
	-- TODO: cast value to proper type before indexing `listeners`.
	return not not (value and listeners[value :: any])
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

--[=[
	Runs the given function and schedules listeners to be notified only once after the function has completed.
    Useful for batching multiple changes.

	@param callback The function to run.
]=]
local function batch(callback: Procedure)
	if batching then
		return callback()
	end

	batching = true

	try(callback, function()
		batching = false
	end)

	for listener in batched do
		try(listener)
	end

	table.clear(batched)
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

--[=[
	Subscribes the listener to the changes of the given atoms.

	@param atoms The atoms to listen to.
	@param listener The function to call when the atoms change.
	@param ref Optionally bind the lifetime of the listener to a value.
]=]
local function connect(atoms: Set<UnknownAtom>, listener: Procedure, ref: unknown?)
	for atom in atoms do
		listeners[atom][listener] = ref or true
	end
end

--[=[
	Unsubscribes the listener from every atom it was connected to.

	@param atoms The atoms to stop listening to.
	@param listener The function to stop calling when the atoms change.
]=]
local function disconnect(atoms: Set<UnknownAtom>, listener: Procedure)
	for atom in atoms do
		listeners[atom][listener] = nil
	end
end

--[=[
	Creates a new atom with the given state.

	@param state The initial state.
	@param options Optional configuration.
	@return A new atom.
]=]
local function atom<T>(state: T, options: AtomOptions<T> | nil): Atom<T>
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

--[=[
	A hook that subscribes to changes in the given atom or molecule.
    The component is re-rendered whenever the state changes.

	If the `dependencies` array is provided, the subscription to the atom or
	molecule is re-created whenever the dependencies change.
    Otherwise, the subscription is created once when the component is mounted.

	@param molecule The atom or molecule to subscribe to.
	@param dependencies An array of values that the subscription depends on.
	@return The current state.
]=]
local function useAtom<State>(molecule: Molecule<State>, dependencies: { unknown } | nil): State
	local React = requireReact()

	local state, setState = React.useState(molecule)

	React.useEffect(function()
		setState(molecule())

		return subscribe(molecule, setState)
	end, dependencies or {})

	return state
end

--[=[
	Runs the given callback immediately and whenever any atom it depends on changes.
    Returns a cleanup function that unsubscribes the callback.

	@param callback The function to run.
	@return A function that unsubscribes the callback.
]=]
local function effect(callback: () -> Procedure | nil): Procedure
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

export type Map =
	(<K0, V0, K1, V1>(fn: Molecule<{ [K0]: V0 }>, mapper: (V0, K0) -> (V1?, K1)) -> Molecule<{ [K1]: V1 }>)
	& (<K0, V0, V1>(fn: Molecule<{ [K0]: V0 }>, mapper: (V0, K0) -> V1?) -> Molecule<{ [K0]: V1 }>)
	& (<K0, V0, K1, V1>(fn: Molecule<{ [K0]: V0 }>, mapper: (V0, K0) -> (V1?, K1?)) -> Molecule<{ [K1]: V1 }>)

--[=[
	Maps each entry in the atom's state to a new key-value pair.
    If the `mapper` function returns `undefined`, the entry is omitted from the resulting map.
	When the atom changes, the `mapper` is called for each entry in the state to compute the new state.

	@param molecule The atom or molecule to map.
	@param mapper The function that maps each entry.
	@return A new atom with the mapped state.
]=]
local function mapped<K0, V0, K1, V1>(molecule: Molecule<{ [K0]: V0 }>, mapper: (V0, K0) -> (V1?, K1?)): Molecule<{ [K1]: V1 }>
	local mappedAtom = atom({})
	local mappedAtomRef = setmetatable({ current = mappedAtom }, WEAK_VALUES_METATABLE)
	local prevMappedItems: { [K1]: V1 } = {}
	local unsubscribe

	unsubscribe = effect(function()
		if not mappedAtomRef.current then
			return unsubscribe()
		end

		local items = molecule()
		local mappedItems = table.clone(peek(mappedAtomRef.current))
		local mappedKeys = {}

		-- TODO: Only call mapper if the item has changed.
		for key, item in items do
			local newItem, newKey = mapper(item, key)
			if newKey == nil then
				newKey = key :: any
			end
			if mappedItems[newKey :: K1] ~= newItem then
				mappedItems[newKey :: K1] = newItem :: V1
			else
				mappedKeys[newKey] = key
			end
		end

		for key in prevMappedItems do
			if mappedKeys[key] == nil and mappedItems[key] == prevMappedItems[key] then
				mappedItems[key] = nil
			end
		end

		prevMappedItems = mappedItems
		mappedAtom(mappedItems)
	end :: any)

	return mappedAtom
end

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

local function NOOP() end

--[=[
	Creates an instance of `factory` for each item in the atom's state, and
	cleans up the instance when the item is removed.
    Returns a cleanup function that unsubscribes all instances.

	@param molecule The atom or molecule to observe.
	@param factory The function that tracks the lifecycle of each item.
	@return A function that unsubscribes all instances.
]=]
local function observe<K, V>(molecule: Molecule<{ [K]: V }>, factory: (value: V, key: K) -> Procedure | nil): Procedure
	local connections: { [K]: () -> () } = {}

	local unsubscribe = effect(function()
		local state = molecule()

		for key, disconnect in connections do
			if state[key] == nil then
				connections[key] = nil
				disconnect()
			end
		end

		for key, value in state do
			if not connections[key] then
				connections[key] = factory(value, key) or NOOP
			end
		end
	end :: any)

	local function cleanup()
		unsubscribe()
		for _, disconnect in connections do
			disconnect()
		end
		table.clear(connections)
	end

	return cleanup
end

local SAFE_KEYS = { string = true, number = true }
local SAFE_VALUES = { string = true, number = true, boolean = true, table = true }

local function isUnsafeTable(object: { [any]: any })
	local keyType = nil
	local objectSize = 0

	-- All keys must have the same type
	for key in object do
		local currentType = type(key)

		if not keyType and SAFE_KEYS[currentType] then
			keyType = currentType
		elseif keyType ~= currentType then
			return true
		end

		objectSize += 1
	end

	-- If there are more keys than the length of the array, it's an array with
	-- non-sequential keys.
	if objectSize > #object and keyType == "number" then
		return true
	end

	return false
end

--[=[
	Validates a value to ensure it can be synced over a remote event.

	@param value The value to validate.
	@param key The key of the value in the table.
	@error Throws an error if the value cannot be synced.
]=]
local function validate(value: any, key: any)
	local typeOfKey = type(key)
	local typeOfValue = type(value)

	if not SAFE_KEYS[typeOfKey] then
		error(`Invalid key type '{typeOfKey}' at key '{key}'`)
	elseif not SAFE_VALUES[typeOfValue] then
		error(`Invalid value type '{typeOfValue}' at key '{key}'`)
	elseif typeOfValue == "table" then
		if getmetatable(value) ~= nil then
			error(`Cannot sync tables with metatables! Got {value} at key '{key}'`)
		elseif isAtom(value) then
			error(`Cannot sync nested atoms! Got atom at key '{key}'`)
		elseif isUnsafeTable(value) then
			error(
				`Cannot sync tables unsupported by remote events! The value has the key '{key}'.\n\n`
					.. "This can be for the following reasons:\n"
					.. "1. The object is an array with non-sequential keys\n"
					.. "2. The object is a dictionary with mixed key types (e.g. string and number)\n\n"
					.. "Read more: https://create.roblox.com/docs/scripting/events/remote#argument-limitations"
			)
		end
	end

	if typeOfValue == "number" then
		if value ~= value then
			error(`Cannot sync NaN at key '{key}'`)
		elseif value == math.huge or value == -math.huge then
			error(`Cannot sync infinity at key '{key}'`)
		end
	elseif typeOfKey == "number" then
		if key == math.huge or key == -math.huge then
			error("Cannot sync infinity as key")
		elseif math.floor(key) ~= key then
			error("Cannot sync non-integer number as key")
		end
	end
end

--[=[
	A special value that denotes the absence of a value. Used to represent
	undefined values in patches.
]=]
local NONE = { __none = "__none" }

local function isNone(value: unknown): boolean
	-- TODO: properly cast to a type
	return type(value) == "table" and (value :: any).__none == "__none"
end

local function diff(prevState: { [any]: any }, nextState: { [any]: any })
	local patches = table.clone(nextState)

	for key, previous in prevState do
		local next = nextState[key]

		if previous == next then
			patches[key] = nil
		elseif next == nil then
			patches[key] = NONE
		elseif type(previous) == "table" and type(next) == "table" then
			patches[key] = diff(previous, next)
		end
	end

	if _G.__DEV__ then
		for key, value in prevState do
			validate(value, key)
		end

		for key, value in nextState do
			if prevState[key] ~= value then
				validate(value, key)
			end
		end
	end

	return patches
end

local function apply(state: any, patches: any): any
	if type(patches) == "table" and patches.__none == "__none" then
		return nil
	elseif type(state) ~= "table" or type(patches) ~= "table" then
		return patches
	end

	local nextState = table.clone(state)
	local stateIsArray = state[1] ~= nil

	for key, patch in patches do
		-- Diff-checking an array produces a sparse array, which will not be
		-- preserved when converted to JSON. To prevent this, we turn string
		-- keys back into numeric keys.
		if stateIsArray and type(key) == "string" then
			key = tonumber(key) or key
		end

		nextState[key] = apply(nextState[key], patch)
	end

	return nextState
end

export type ClientOptions = {
	--[=[
		The atoms to synchronize with the server.
	]=]
	atoms: { [string]: UnknownAtom },
}

export type ClientSyncer = {
	--[=[
		Applies a patch or initializes the state of the atoms with the given
		payload from the server.

		@param ...payloads The patches or hydration payloads to apply.
	]=]
	sync: (self: ClientSyncer, ...SyncPayload) -> (),
}

--[=[
	Creates a `ClientSyncer` object that receives patches from the server and
	applies them to the local state.

	@param options The atoms to synchronize with the server.
	@return A `ClientSyncer` object.
]=]
local function client(options: ClientOptions): ClientSyncer
	local atoms = options.atoms
	local self = {} :: ClientSyncer

	-- Apply the state changes sent by the server.
	function self:sync(...)
		for index = 1, select("#", ...) do
			local payload = select(index, ...)

			for key, state in payload.data do
				if payload.type == "patch" then
					atoms[key](apply(atoms[key](), state))
				else
					atoms[key](state)
				end
			end
		end
	end

	return self
end

export type ServerOptions = {
	--[=[
		The atoms to synchronize with the client.
	]=]
	atoms: { [string]: UnknownAtom },

	--[=[
		The interval at which to send patches to the client, in seconds.
		Defaults to `0` (patches are sent up to once per frame). Set to a
		negative value to disable automatic syncing.
	]=]
	interval: number?,

	--[=[
		Whether the history of state changes since the client's last update
		should be preserved. This is useful for values that change multiple times
		per frame, where each individual change is important. Defaults to `false`.
	]=]
	preserveHistory: boolean?,
}

type ServerSyncer = {
	--[=[
		Sets up a subscription to each atom that schedules a patch to be sent to
		the client whenever the state changes. When a change occurs, the `callback`
		is called with the player and the payload to send.

		Note that the `payload` object should not be mutated. If you need to
		modify the payload, apply the changes to a copy of the object.

		@param callback The function to call when the state changes.
		@return A cleanup function that unsubscribes all listeners.
	]=]
	connect: (self: ServerSyncer, callback: (player: Player, ...SyncPayload) -> ()) -> Procedure,

	--[=[
		Hydrates the client's state with the server's state. This should be
		called when a player joins the game and requires the server's state.

		@param player The player to hydrate.
	]=]
	hydrate: (self: ServerSyncer, player: Player) -> (),
}

--[=[
	Creates a `ServerSyncer` object that sends patches to the client and
	hydrates the client's state.

	@param options The atoms to synchronize with the client.
	@return A `ServerSyncer` object.
]=]
local function server(options: ServerOptions): ServerSyncer
	local self = {} :: ServerSyncer
	local sync: (player: Player, payload: SyncPayload) -> ()
	local snapshots: { { [string]: unknown } } = {}
	local changed = false

	-- Start the interval to send state patches over the network.
	function self:connect(callback)
		local cleanups = {}
		sync = callback

		local function getSnapshot()
			local snapshot: { [string]: unknown } = {}
			for key, atom in options.atoms do
				snapshot[key] = atom()
			end
			return snapshot
		end

		local function pushSnapshot(key: string, current: unknown, previous: unknown)
			if not options.preserveHistory then
				if snapshots[2] then
					snapshots[2][key] = current
				else
					snapshots[2] = getSnapshot()
				end
				return
			end

			local lastSnapshot = snapshots[#snapshots]
			local previousSnapshot = snapshots[#snapshots - 1]

			-- Optimize snapshots by updating the most recent snapshot if the
			-- previous and current values are the same, since this allows us
			-- to group multiple changes into a single snapshot.
			if previousSnapshot and previousSnapshot[key] == previous and lastSnapshot[key] == previous then
				lastSnapshot[key] = current
			else
				local nextSnapshot = table.clone(lastSnapshot)
				nextSnapshot[key] = current
				table.insert(snapshots, nextSnapshot)
			end
		end

		-- Populate the initial state and snapshot for each atom.
		-- Subscribe to each atom and update the state when it changes.
		for key, atom in options.atoms do
			cleanups[key] = subscribe(atom, function(current, previous)
				pushSnapshot(key, current, previous)
				changed = true
			end)
		end

		snapshots[1] = getSnapshot()

		local function onInterval()
			if not changed then
				return
			end

			local payloads: { SyncPayload } = {}
			local lastSnapshot

			for index, snapshot in snapshots do
				lastSnapshot = snapshot

				if index == 1 then
					continue
				end

				table.insert(payloads, {
					type = "patch",
					data = diff(snapshots[index - 1], snapshot),
				})
			end

			snapshots = { lastSnapshot }
			changed = false

			for _, player in Players:GetPlayers() do
				callback(player, unpack(payloads))
			end
		end

		local interval = options.interval or 0
		local connection: RBXScriptConnection | nil

		if interval >= 0 then
			local currentTime = 0

			connection = RunService.Heartbeat:Connect(function(deltaTime)
				currentTime += deltaTime
				if currentTime >= interval then
					currentTime = 0
					onInterval()
				end
			end)
		end

		return function()
			if connection then
				connection:Disconnect()
			end

			for _, cleanup in cleanups do
				cleanup()
			end
		end
	end

	-- Send the initial state to a player when they join the server.
	function self:hydrate(player)
		assert(sync, "connect() must be called before hydrate()")

		sync(player, {
			type = "init",
			data = snapshots[#snapshots],
		})
	end

	return self
end

local exports = {
	computed = computed,
	effect = effect,
	mapped = mapped,
	observe = observe,
	useAtom = useAtom,
	batch = batch,
	capture = capture,
	isAtom = isAtom,
	notify = notify,
	peek = peek,
	subscribe = subscribe,

	--[=[
        Synchronizes state between the client and server.
        The server sends patches to the client, which applies them to its local state.
    ]=]
	sync = {
		client = client,
		server = server,
		isNone = isNone,
	},
}

table.freeze(exports)

return exports
