import type { Molecule } from "./types";

/**
 * Creates a read-only atom that derives its state from one or more atoms.
 * Used to avoid unnecessary recomputations if multiple listeners depend on the same molecule.
 *
 * @param molecule The function that produces the state.
 * @param options Optional configuration.
 * @returns A new read-only atom.
 */
declare function computed<TState>(molecule: Molecule<TState>, options?: AtomOptions<TState>): Molecule<TState>;

export = computed;
