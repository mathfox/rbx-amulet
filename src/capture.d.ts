import type { Molecule } from "./types";

/**
 * Captures all atoms that are read during the function call and returns them along with the result of the function.
 * Useful for tracking dependencies.
 *
 * @param molecule The function to run.
 * @returns A tuple containing the captured atoms and the result of the function.
 */
declare function capture<TState>(molecule: Molecule<TState>): LuaTuple<[dependencies: Set<UnknownAtom>, state: TState]>;

export = capture;
