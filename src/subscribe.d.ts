import type { CleanupCallback, Molecule } from "./types";

/**
 * Subscribes to changes in the given atom or molecule.
 * The callback is called with the current state and the previous state immediately after a change occurs.
 *
 * @param molecule The atom or molecule to subscribe to.
 * @param callback The function to call when the state changes.
 * @returns A function that unsubscribes the callback.
 */
declare function subscribe<TState>(
	molecule: Molecule<TState>,
	callback: (state: TState, prev: TState) => void,
): CleanupCallback;

export = subscribe;
