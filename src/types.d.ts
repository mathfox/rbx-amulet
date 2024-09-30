export type CleanupCallback = () => void;

/**
 * A function that depends on one or more atoms and produces a state.
 * Can be used to derive state from atoms.
 *
 * @returns The current state.
 */
export type Molecule<TState> = () => TState;

export interface AtomOptions<TState> {
	/**
	 * A function that determines whether the state has changed.
	 * By default, a strict equality check (`===`) is used.
	 */
	readonly equals?: (prev: TState, next: TState) => boolean;
}
